require 'bindata'

module AMF
  module Pure    
    class MetaString < BinData::Primitive
      int16be :len, :value => lambda { stream.length }
      string :stream, :read_length => :len
        
      def get
        self.stream
      end
 
      def set(value)
        self.stream = value
      end
    end
    
    class DataString < BinData::Record
      int32be :len, :value => lambda { stream.length }
      int8 :amf0Type #HACK - IGNORE - needed to unwrap AMF0 Wrapper
      int32be :amf0ArrayLength #HACK - IGNORE - needed to unwrap AMF0 Wrapper
      int8 :amf3Type
      string :stream, :read_length => lambda { len - 6 } #:len
    end
    
    class Header < BinData::Record
      meta_string :name
      int8 :required
      data_string :data
    end
    
    class Body < BinData::Record
      meta_string :target
      meta_string :response
      data_string :data
    end
    
    class Request < BinData::Record
      int8 :amf_version
      int8 :client_version
      uint16be :header_count
      array :headers, :type => :header, :initial_length => :header_count
      int16be :body_count
      array :bodies, :type => :body, :initial_length => :body_count
    end
  end
end