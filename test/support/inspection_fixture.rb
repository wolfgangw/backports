# frozen_string_literal: true

require "tmpdir"
require "stringio"
require "digest"
require "dcp_inspect"
require "dcp_inspect/inspection/runtime"

module InspectionFixture
  Runtime = DcpInspect::Inspection::Runtime
  V = DcpInspect::Inspection::Vocabulary

  def fixture_uuid(number)
    format("00000000-0000-4000-8000-%012d", number)
  end

  def with_inspection_fixture
    Dir.mktmpdir("metadata-inspection-") do |directory|
      @directory = directory
      @metadata = {
        "picture.mxf" => { "EssenceType" => V::Pictures, "Label Set Type" => "MXF Interop",
          "AssetUUID" => fixture_uuid(4), "EncryptedEssence" => "No", "EditRate" => "24/1",
          "SampleRate" => "24/1", "ContainerDuration" => "240", "DecompositionLevels" => "5",
          "StoredWidth" => "1998", "StoredHeight" => "1080" },
        "sound.mxf" => { "EssenceType" => V::Audio, "Label Set Type" => "MXF Interop",
          "AssetUUID" => fixture_uuid(5), "EncryptedEssence" => "No", "EditRate" => "24/1",
          "ContainerDuration" => "240", "ChannelFormat" => "0", "ChannelCount" => "6",
          "AudioSamplingRate" => "48000/1", "QuantizationBits" => "24", "BlockAlign" => "18" }
      }
      File.write(File.join(directory, "picture.mxf"), "picture bytes")
      File.write(File.join(directory, "sound.mxf"), "sound bytes")
      write_cpl
      write_package
      yield
    end
  end

  def reference(kind, number, extra = "", rate: "24 1", duration: "240", intrinsic: "240", entry: "0")
    "<#{kind}><Id>urn:uuid:#{fixture_uuid(number)}</Id><EditRate>#{rate}</EditRate>" \
      "<IntrinsicDuration>#{intrinsic}</IntrinsicDuration><EntryPoint>#{entry}</EntryPoint>" \
      "#{duration.nil? ? '' : "<Duration>#{duration}</Duration>"}#{extra}</#{kind}>"
  end

  def write_cpl(reels: nil, namespace: V::Interop_cpl)
    reels ||= [reference("MainPicture", 4) + reference("MainSound", 5)]
    xml = "<CompositionPlaylist xmlns='#{namespace}'><Id>urn:uuid:#{fixture_uuid(3)}</Id>" \
      "<IssueDate>2026-01-01T00:00:00Z</IssueDate><ContentTitleText>Metadata test</ContentTitleText>" \
      "<ContentKind>feature</ContentKind><ReelList>" + reels.each_with_index.map { |assets, index|
        "<Reel><Id>urn:uuid:#{fixture_uuid(10 + index)}</Id><AssetList>#{assets}</AssetList></Reel>"
      }.join + "</ReelList></CompositionPlaylist>"
    File.write(File.join(@directory, "CPL.xml"), xml)
  end

  def write_package(assets: nil)
    assets ||= [[3, "CPL.xml", "text/xml;asdcpKind=CPL"],
      [4, "picture.mxf", "application/x-smpte-mxf;asdcpKind=Picture"],
      [5, "sound.mxf", "application/x-smpte-mxf;asdcpKind=Sound"]]
    pkl_assets = assets.map do |number, name, type|
      path = File.join(@directory, name)
      "<Asset><Id>urn:uuid:#{fixture_uuid(number)}</Id><Hash>#{Digest::SHA1.file(path).base64digest}</Hash>" \
        "<Size>#{File.size(path)}</Size><Type>#{type}</Type></Asset>"
    end.join
    File.write(File.join(@directory, "PKL.xml"), "<PackingList xmlns='#{V::Interop_pkl}'>" \
      "<Id>urn:uuid:#{fixture_uuid(2)}</Id><AssetList>#{pkl_assets}</AssetList></PackingList>")
    mapped = [[2, "PKL.xml", ""], *assets].uniq { |number, name, _| [number, name] }.map do |number, name, _|
      "<Asset><Id>urn:uuid:#{fixture_uuid(number)}</Id>#{number == 2 ? '<PackingList/>' : ''}" \
        "<ChunkList><Chunk><Path>#{name}</Path></Chunk></ChunkList></Asset>"
    end.join
    File.write(File.join(@directory, "ASSETMAP"), "<AssetMap xmlns='#{V::Interop_am}'>" \
      "<Id>urn:uuid:#{fixture_uuid(1)}</Id><AssetList>#{mapped}</AssetList></AssetMap>")
  end

  def inspect_fixture(*flags, audio: false)
    options = DcpInspect::CLI::Options.parse(["--nh", *(!audio ? ["--na"] : []), "--no-schema", *flags])
    metadata = @metadata
    inspector = ->(path) { metadata[File.basename(path)] }
    with_tool_method(:asdcplib_version, -> { [2, 13, 2] }) do
      with_tool_method(:mxf_inspect, inspector) do
        runtime = Runtime.new(options: options, stdout: StringIO.new)
        # Metadata fixtures deliberately use placeholder essence bytes. Media
        # mechanism/integration tests opt into the real bounded header scanner.
        runtime.define_singleton_method(:inspect_media_headers) { |_path, _meta| nil } unless @inspect_media
        runtime.call(@directory)
      end
    end
  end

  def with_tool_method(name, replacement)
    singleton = Runtime::MxfTools.singleton_class
    owned = singleton.instance_methods(false).include?(name)
    original = Runtime::MxfTools.method(name)
    singleton.remove_method(name) if owned
    Runtime::MxfTools.define_singleton_method(name, replacement)
    yield
  ensure
    singleton.remove_method(name) if singleton.instance_methods(false).include?(name)
    Runtime::MxfTools.define_singleton_method(name, original) if owned
  end
end
