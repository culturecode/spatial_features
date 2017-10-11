module Chroma
  class Color
    module Serializers
      # Google's Fusion Table colouring expects the alpha value in the last position, not the first
      def to_ft_hex
        [
         to_2char_hex(@rgb.r),
         to_2char_hex(@rgb.g),
         to_2char_hex(@rgb.b),
         to_2char_hex(alpha * 255)
        ].join('')
      end
    end
  end
end
