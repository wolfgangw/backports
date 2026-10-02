# frozen_string_literal: true

require "minitest/autorun"
require "dcp_inspect"

class ModelTest < Minitest::Test
  def test_builds_and_serializes_package_relationships
    run = DcpInspect::Model::InspectionRun.new("/dcp")
    assetmap = run.assetmap("am", path: "ASSETMAP", base: ".")
    packing_list = run.packing_list("pkl", path: "PKL.xml", assetmap_id: "am")
    composition = run.composition("cpl", path: "CPL.xml", packing_list_id: "pkl")
    asset = run.asset("picture", path: "picture.mxf", assetmap_id: "am", packing_list_id: "pkl")
    reel_asset = run.reel_asset("cpl", 1, "picture", kind: "MainPicture", duration: 24, edit_rate: 24)

    assert_includes assetmap.packing_lists, packing_list
    assert_includes packing_list.compositions, composition
    assert_includes packing_list.assets, asset
    assert_equal asset, reel_asset.asset

    serialized = run.to_h
    assert_equal 1, serialized.fetch(:packages).length
    assert_equal 1, serialized.fetch(:assetmaps).length
    assert_equal 1, serialized.fetch(:packing_lists).length
    assert_equal 1, serialized.fetch(:compositions).length
  end
end
