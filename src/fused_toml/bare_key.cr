module FusedTOML
  private module BareKey
    def self.byte?(byte : UInt8) : Bool
      char = byte.chr
      char.ascii_alphanumeric? || char.in?('-', '_')
    end

    def self.valid?(key : String) : Bool
      !key.empty? && key.each_byte.all? { |byte| byte?(byte) }
    end
  end
end
