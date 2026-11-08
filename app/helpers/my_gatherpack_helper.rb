module MyGatherpackHelper
  def my_gatherpack_menu
    @my_gatherpack_menu ||= MyGatherpack::Menu.new(current_user)
  end

  def site_title
    Settings[:title].presence || "GatherPack"
  end
end
