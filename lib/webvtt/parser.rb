module WebVTT

  def self.read(file)
    File.new(file)
  end

  def self.from_blob(content)
    Blob.new(content)
  end

  def self.convert_from_srt(srt_file, output=nil)
    if !::File.exist?(srt_file)
      raise InputError, "SRT file not found"
    end

    srt = ::File.read(srt_file)
    output ||= srt_file.gsub(".srt", ".vtt")

    # normalize timestamps in srt
    srt.gsub!(/(:|^)(\d)(,|:)/, '\10\2\3')
    # convert timestamps and save the file
    srt.gsub!(/([0-9]{2}:[0-9]{2}:[0-9]{2})([,])([0-9]{3})/, '\1.\3')
    # normalize new line character
    srt.gsub!("\r\n", "\n")

    srt = "WEBVTT\n\n#{srt}".strip
    ::File.open(output, "w") {|f| f.write(srt)}

    return File.new(output)
  end

  class Blob
    attr_reader :header
    attr_accessor :cues

    def initialize(content = nil)
      @cues = []

      if content
        parse(
          content.gsub("\r\n", "\n").gsub("\r","\n") # normalizing new line character
        )
      else
        @header = 'WEBVTT'
      end
    end

    def to_webvtt
      [@header, @cues.map(&:to_webvtt)].flatten.join("\n\n")
    end

    def total_length
      @cues.last.end_in_sec
    end

    def actual_total_length
      @cues.last.end_in_sec - @cues.first.start_in_sec
    end

    def parse(content)
      # remove bom first
      content.gsub!("\uFEFF", '')

      cues = content.split(/\n\n+/)

      @header = cues.shift
      header_lines = @header.split("\n").map(&:strip)
      if (header_lines[0] =~ /^WEBVTT/).nil?
        raise MalformedFile, "Not a valid WebVTT file"
      end

      @cues = []
      cues.each do |cue|
        cue_parsed = Cue.parse(cue.strip)
        if !cue_parsed.text.nil?
          @cues << cue_parsed
        end
      end
      @cues
    end
  end

  class File < Blob
    attr_reader :path, :filename

    def initialize(webvtt_file)
      if !::File.exist?(webvtt_file)
        raise InputError, "WebVTT file not found"
      end

      @path = webvtt_file
      @filename = ::File.basename(@path)
      super(::File.read(webvtt_file))
    end

    def save(output=nil)
      output ||= @path.gsub(".srt", ".vtt")

      ::File.open(output, "w") do |f|
        f.write(to_webvtt)
      end
      return output
    end
  end

  class Cue
    attr_accessor :identifier, :start, :end, :style, :text

    def initialize(cue = nil)
      @content = cue
      @style = {}
    end

    def self.parse(cue)
      cue = Cue.new(cue)
      cue.parse
      return cue
    end

    def to_webvtt
      res = ""
      if @identifier
        res << "#{@identifier}\n"
      end
      res << "#{@start} --> #{@end} #{@style.map{|k,v| "#{k}:#{v}"}.join(" ")}".strip + "\n"
      res << @text

      res
    end

    def self.timestamp_in_sec(timestamp)
      Timestamp.new(timestamp).to_seconds
    end

    def start_in_sec
      @start.to_seconds
    end

    def end_in_sec
      @end.to_seconds
    end

    def length
      @end.to_seconds - @start.to_seconds
    end

    def offset_by(offset_secs)
      offset_millis = (offset_secs * 1000).round(3)
      
      @start += offset_millis
      @end += offset_millis
    end

    def parse
      lines = @content.split("\n").map(&:strip)

      # it's a note, ignore
      return if lines[0] =~ /NOTE/

      if !lines[0].include?("-->")
        @identifier = lines[0]
        lines.shift
      end

      if lines.empty?
        return
      end

      if lines[0].match(/(([0-9]{1,2}:)?[0-5][0-9]:[0-5][0-9]\.[0-9]{3}) -+> (([0-9]{2}:)?[0-5][0-9]:[0-5][0-9]\.[0-9]{3})(.*)/)
        @start = Timestamp.new $1
        @end = Timestamp.new $3
        @style = Hash[$5.strip.split(" ").map{|s| s.split(":").map(&:strip) }]
      else
        raise WebVTT::MalformedFile
      end

      @text = lines[1..-1].join("\n")
    end
  end

  class Timestamp
    def self.parse_milliseconds(timestamp)
      match = timestamp.match(/^(?:(?<hours>[0-9]{1,2}):)?(?<minutes>[0-5][0-9]):(?<seconds>[0-5][0-9])\.(?<millis>[0-9]{3})$/)
      raise ArgumentError.new("Invalid WebVTT timestamp format: #{timestamp.inspect}") unless match

      milliseconds = match[:millis].to_i
      milliseconds += match[:seconds].to_i * 1000
      milliseconds += match[:minutes].to_i * 60 * 1000
      milliseconds += match[:hours].to_i * 60 * 60 * 1000

      milliseconds
    end

    def initialize(timestamp)
      if timestamp.is_a?(Integer)
        @milliseconds = timestamp
      elsif timestamp.is_a?(String)
        @milliseconds = Timestamp.parse_milliseconds(timestamp)
      else
        raise ArgumentError.new("timestamp is not Integer nor a String")
      end
    end

    def to_s
      total_seconds = @milliseconds / 1000

      hours = total_seconds / 60 / 60
      minutes = (total_seconds / 60) % 60
      seconds = total_seconds % 60
      milliseconds = @milliseconds % 1000

      sprintf("%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    end

    def to_i
      @milliseconds
    end

    def to_seconds
      (to_i / 1000.0).round(3)
    end

    def +(other)
      Timestamp.new(self.to_i + other.to_i)
    end
  end
end
