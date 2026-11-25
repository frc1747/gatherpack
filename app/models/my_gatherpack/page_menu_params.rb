module MyGatherpack
  # Lets the Page form's "Show in the menu" tick box through while the menu
  # that shows it is on.
  module PageMenuParams
    private

    def page_params
      return super unless MyGatherpack.enabled?

      super.merge(params.require(:page).permit(:show_in_menu))
    end
  end
end
