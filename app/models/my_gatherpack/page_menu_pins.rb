module MyGatherpack
  # Pins name a Page by a string key, so there's no association to cascade
  # through: a deleted Page takes its pins with it here.
  module PageMenuPins
    extend ActiveSupport::Concern

    included do
      after_destroy { MenuPin.where(path_key: MenuPin.page_key(self)).delete_all }
    end
  end
end
