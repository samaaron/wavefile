module WaveFile
  # Error that is raised when trying to read from a Reader instance that has been closed.
  class ReaderClosedError < IOError; end

  # Provides the ability to read sample data out of a wave file, as well as query a 
  # wave file about its metadata (e.g. number of channels, sample rate, etc).
  #
  # When constructing a Reader a block can be given. All data should be read inside this 
  # block, and when the block exits the Reader will automatically be closed.
  #
  #     Reader.new("my_file.wav") do |reader|
  #       # Read sample data here
  #     end
  #
  # Alternately, if a block isn't given you should make sure to call close when finished reading.
  #
  #     reader = Reader.new("my_file.wav")
  #     # Read sample data here
  #     reader.close
  class Reader
    # Returns a Reader object that is ready to start reading the specified file's sample data. 
    #
    # io_or_file_name - The name of the wave file to read from,
    #                   or an open IO object to read from.
    # format - The format that read sample data should be returned in 
    #          (default: the wave file's internal format).
    #
    # Returns a Reader object that is ready to start reading the specified file's sample data.
    # Raises Errno::ENOENT if the specified file can't be found
    # Raises InvalidFormatError if the specified file isn't a valid wave file
    def initialize(io_or_file_name, format=nil)
      if io_or_file_name.is_a?(String)
        @io = File.open(io_or_file_name, "rb")
        @io_source = :file_name
      else
        @io = io_or_file_name
        @io_source = :io
      end

      @closed = false

      begin
        riff_reader = ChunkReaders::RiffReader.new(@io, format)
      rescue InvalidFormatError
        raise InvalidFormatError, "Does not appear to be a valid Wave file"
      end
      
      @data_chunk_reader = riff_reader.data_chunk_reader

      if block_given?
        begin
          yield(self)
        ensure
          close
        end
      end
    end


    # Reads sample data of the into successive Buffers of the specified size, until there is no more 
    # sample data to be read. When all sample data has been read, the Reader is automatically closed. 
    # Each Buffer is passed to the given block.
    #
    # Note that sample_frame_count indicates the number of sample frames to read, not number of samples. 
    # A sample frame include one sample for each channel. For example, if sample_frame_count is 1024, then 
    # for a stereo file 1024 samples will be read from the left channel, and 1024 samples will be read from 
    # the right channel.
    #
    # sample_frame_count - The number of sample frames to read into each Buffer from each channel. The number 
    #                      of sample frames read into the final Buffer could be less than this size, if there 
    #                      are not enough remaining.
    #
    # Returns nothing.
    def each_buffer(sample_frame_count=4096)
      begin
        while true do
          yield(read(sample_frame_count))
        end
      rescue EOFError
        close
      end
    end


    # Reads the specified number of sample frames from the wave file into a Buffer. Note that the Buffer will have 
    # at most sample_frame_count sample frames, but could have less if the file doesn't have enough remaining.
    #
    # sample_frame_count - The number of sample frames to read. Note that each sample frame includes a sample for 
    #                      each channel.
    #
    # Returns a Buffer containing sample_frame_count sample frames
    # Raises UnsupportedFormatError if file is in a format that can't be read by this gem
    # Raises ReaderClosedError if the Writer has been closed.
    # Raises EOFError if no samples could be read due to reaching the end of the file
    def read(sample_frame_count)
      if @closed
        raise ReaderClosedError
      end

      @data_chunk_reader.read(sample_frame_count)
    end


    # Returns true if the Reader is closed, and false if it is open and available for reading.
    def closed?
      @closed
    end


    # Closes the Reader. After a Reader is closed, no more sample data can be read from it.
    # Note: If the Reader is constructed from an open IO instance (as opposed to a file name),
    # the IO instance will _not_ be closed. You'll have to manually close it yourself.
    #
    # Returns nothing.
    # Raises ReaderClosedError if the Reader is already closed.
    def close
      if @closed
        raise ReaderClosedError
      end

      if @io_source == :file_name
        @io.close
      end

      @closed = true
    end

    # Returns a Duration instance for the total number of sample frames in the file
    def total_duration
      Duration.new(total_sample_frames, @data_chunk_reader.format.sample_rate)
    end

    # Returns a Format object describing the sample format of the Wave file being read.
    # This is not necessarily the format that the sample data will be read as - to determine
    # that, use #format.
    def native_format
      @data_chunk_reader.raw_native_format
    end

    # Returns true if this is a valid Wave file and contains sample data that is in a format
    # that this class can read, and returns false if this is a valid Wave file but does not
    # contain a sample format supported by this class.
    def readable_format?
      @data_chunk_reader.readable_format
    end

    # Returns a Format object describing how sample data is being read from the Wave file (number of 
    # channels, sample format and bits per sample, etc). Note that this might be different from the 
    # underlying format of the Wave file on disk.
    def format
      @data_chunk_reader.format
    end

    # Returns the index of the sample frame which is "cued up" for reading. I.e., the index 
    # of the next sample frame that will be read. A sample frame contains a single sample 
    # for each channel. So if there are 1,000 sample frames in a stereo file, this means 
    # there are 1,000 left-channel samples and 1,000 right-channel samples.
    def current_sample_frame
      @data_chunk_reader.current_sample_frame
    end

    # Returns the total number of sample frames in the file. A sample frame contains a single 
    # sample for each channel. So if there are 1,000 sample frames in a stereo file, this means 
    # there are 1,000 left-channel samples and 1,000 right-channel samples.
    def total_sample_frames
      @data_chunk_reader.total_sample_frames
    end
  end
end
