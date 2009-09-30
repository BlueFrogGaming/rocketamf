require 'date'
require 'rexml/document'
require 'amf/pure/io_helpers'

module AMF
  module Pure
    module Serializer
      class State    
        def self.from_state(opts)
          opts ||= new
        end
        
        def initialize(opts = {})
          @dynamic = false
          # integer cache and float cache are used to avoid 
          # processing the numbers multiple times
          @integer_cache = {}
          @float_cache   = {}
          # string and object cache are used as reference
          # tables which are further discussed in the AMF specs
          @string_cache  = {}
          @object_cache  = {}
        end
        attr_accessor :dynamic,
                      :integer_cache, 
                      :float_cache,
                      :string_cache,
                      :object_cache
                
        # if string has been referenced, returns the index of the reference
        # in the implicit string reference tabel. If no reference is found
        # sets the reference to the next index in the implicit strings table
        # and returns nil
        def string_cache(str)
          index = @string_cache.fetch(str) { |str|
            @string_cache[str] = @string_cache.length
            nil
          }
          header_for_cache(index) if index
        end
        
        # if object has been referenced, returns the index of the reference
        # in the implicit object reference table. If no reference is found
        # sets the reference to the next index in the implicit objects table
        # and returns nil.
        def object_cache(obj)
          index = @object_cache.fetch(obj.amf_id) { |amf_id|
            @object_cache[amf_id] = @object_cache.length
            nil
          }
          header_for_cache(index) if index
        end
        
        def header_for_cache(index)
          header = index << 1 # shift value left to leave a low bit of 0
          AMF::Pure::IOHelpers.pack_integer(header, self)
        end
      end
                  
      module SerializerMethods 
        module NilClass
          def to_amf(*)
            '' << AMF3_NULL_MARKER
          end
        end
        
        module FalseClass
          def to_amf(*)
            '' << AMF3_FALSE_MARKER
          end
        end
        
        module TrueClass
          def to_amf(*)
            '' << AMF3_TRUE_MARKER
          end
        end
        
        module Bignum
          def to_amf(state = nil, *)
            self.to_f.to_amf(state)
          end
        end
        
        module Integer
          def to_amf(state = nil, *)
            if self >= MIN_INTEGER && self <= MAX_INTEGER #check valid range for 29 bits
              write_integer(state)
            else #overflow to a double
              self.to_f.to_amf(state)
            end
          end
          
          protected
          
          def write_integer(state = nil)
            output = ''
            output << AMF3_INTEGER_MARKER
            output << AMF::Pure::IOHelpers.pack_integer(self)
          end
        end
        
        module Float
          def to_amf(state = nil, *)
            output = ''
            output << AMF3_DOUBLE_MARKER
            output << AMF::Pure::IOHelpers.pack_double(self, state)
          end
        end
        
        module String
          def to_amf(state = nil, *)
            output = ''
            output << AMF3_STRING_MARKER
            output << write_string(state)
          end
          
          def write_string(state = nil)
            output = ''
            if self == ''
              output << EMPTY_STRING
            elsif state && (cache_header = state.string_cache(self))
              output << cache_header
            else
              output << header_for_string(state) 
              output << self
            end
          end
          
          private
          
          def header_for_string(state = nil)
            header = self.length << 1 # make room for a low bit of 1
            header = header | 1 # set the low bit to 1
            AMF::Pure::IOHelpers.pack_integer(header, state)
          end
        end
        
        module Symbol
          def to_amf(state = nil, *)
            self.to_s.to_amf(state)
          end
        end
        
        module Array
          def to_amf(state = nil, *)
            output = ''
            output << AMF3_ARRAY_MARKER
          
            state = SerializerState.from_state(state)
            if cache_header =  state.object_cache(self)
              output << cache_header
            else
              output << header_for_array(state)
              # AMF only encodes strict, dense arrays by the AMF spec
              # so the dynamic portion is empty
              output << CLOSE_DYNAMIC_ARRAY
              self.each do |val|
                output << val.to_amf(state)
              end
            end
            output
          end
          
          private
          
          def header_for_array(state = nil)
            header = self.length << 1 # make room for a low bit of 1
            header = header | 1 # set the low bit to 1
            AMF::Pure::IOHelpers.pack_integer(header, state)
          end
        end
   
        module Object
          def to_amf(state = nil, *)
            output = ''
            output << AMF3_OBJECT_MARKER
            
            state = SerializerState.from_state(state) 
            if cache_header = state.object_cache(self)
              output << cache_header
            else
              if state && !state.dynamic
                state.dynamic = true
                output << DYNAMIC_OBJECT
              end
              output << ANONYMOUS_OBJECT
              output << serialize_properties(state)
              output << CLOSE_DYNAMIC_OBJECT
            end
          end
          
          protected
          
          def amf_id
            object_id
          end
          
          private
            
          # unmapped object
          #OPTIMIZE: keep a hash of classes that come through here
          # and store in a hash keyed by obj.class
          # if the obj.class is in the hash, loop over the hash of
          # public methods
          # find all public methods belonging to this object alone
          def serialize_properties(state = nil)
            output = ''
            self.public_methods(false).each do |method_name|
              # and write them to the stream if they take no arguments
              method_def = self.method(method_name)
              if method_def.arity == 0
                output << method_name.to_s.write_string(state)
                output << self.send(method_name).to_amf(state)
              end
            end
            output
          end
        end
        
        module Hash
          private
          
          def serialize_properties(state = nil)
            output = ''
            self.each do |key, value|
              output << key.to_s.write_string(state) # easy for both string and symbol keys
              output << value.to_amf(state)
            end
            output
          end
        end
        
        module Time
          def to_amf(state = nil, *)
            output = ''
            output << AMF3_DATE_MARKER
            
            self.utc unless self.utc?
            seconds = (self.to_f * 1000).to_i
            
            if state && (cache_header = state.object_cache(self))
              output << cache_header
            else
              output << AMF::Pure::IOHelpers.pack_integer(AMF3_NULL_MARKER)
              output << AMF::Pure::IOHelpers.pack_double(seconds, state)
            end
          end
        end
        
        module Date
          def to_amf(state = nil, *)
            output = ''
            output << AMF3_DATE_MARKER
            
            seconds = ((self.strftime("%s").to_i) * 1000).to_i
            
            if state && (cache_header = state.object_cache(self))
              output << cache_header
            else
              output << AMF::Pure::IOHelpers.pack_integer(AMF3_NULL_MARKER)
              output << AMF::Pure::IOHelpers.pack_double(seconds, state)
            end
          end
        end
        
        module REXML
          class Document
            def to_amf(state = nil, *)
              AMF.write_xml(self, state)
            end
          end
        end
      end 
    end
  end
end