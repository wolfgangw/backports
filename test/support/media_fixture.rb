# frozen_string_literal: true
module MediaFixture
  def klv(key, value)
    key + [0x84, value.bytesize].pack('CN') + value
  end

  def mxf(*packets)
    partition = ['060e2b34020501010d01020101020400'].pack('H*')
    klv(partition, ''.b) + packets.join
  end

  def jpeg2000(width: 1998, height: 1080, block_style: 0, profile: 3)
    siz = [profile].pack('n') + [width, height, 0, 0, width, height, 0, 0].pack('N8') + [3].pack('n') + [11, 1, 1].pack('C*') * 3
    cod = [1, 4, 0, 1, 1, 5, 3, 3, block_style, 0, 0x77, *([0x88] * 5)].pack('C*')
    segment = ->(marker, data) { [marker, data.bytesize + 2].pack('nn') + data }
    tile = ->(i) { segment.call(0xff90, [0, 15, i, 3].pack('nNCC')) + [0xff93].pack('n') + 'x' }
    [0xff4f].pack('n') + segment.call(0xff51, siz) + segment.call(0xff52, cod) + segment.call(0xff5c, [0x22].pack('C')) +
      segment.call(0xff55, [0, 0x50].pack('CC') + [0, 15].pack('CN') * 3) + 3.times.map { |i| tile.call(i) }.join + [0xffd9].pack('n')
  end

  class Bits
    def initialize
      @text = +''
    end
    def put(value, width)
      @text << value.to_s(2).rjust(width, '0')
      self
    end
    def align
      @text << '0' until @text.size % 8 == 0
      self
    end
    def bytes
      align
      [@text].pack('B*')
    end
  end

  def iab_element(type, body)
    encoded = type < 255 ? [type].pack('C') : [255, type].pack('Cn')
    size = body.size < 255 ? [body.size].pack('C') : [255, body.size].pack('Cn')
    encoded + size + body
  end

  def iab_object(id, audio_id: 0, children: [])
    bits = Bits.new.put(id, 8).put(audio_id, 8).put(0, 1).put(0, 1)
    bits.put(0, 2).put(1, 3).put(32767, 16).put(32767, 16).put(0, 16)
    bits.put(0, 1).put(0, 1).put(1, 2).put(0, 4).put(0, 2)
    7.times { bits.put(0, 1) }
    bits.align.put(0, 8).put(children.size, 8)
    iab_element(64, bits.bytes + children.join)
  end

  def iab_bed(id = 1)
    bits = Bits.new.put(id, 8).put(0, 1).put(1, 4)
    bits.put(0, 4).put(0, 8).put(0, 2).put(0, 1).put(0x180, 10)
    bits.align.put(0, 8).put(0, 8)
    iab_element(16, bits.bytes)
  end

  def iab_frame(elements = [iab_bed, iab_object(1)])
    body = [1, 0x10, elements.size, elements.size].pack('C*') + elements.join
    frame = iab_element(8, body)
    [1, 0, 2, frame.size].pack('CNCN') + frame
  end
end
