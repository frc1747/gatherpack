module Orders
  class VendorsController < BaseController
    before_action :set_vendor, only: %i[show edit update destroy]

    # GET /orders/vendors
    def index
      @vendors = policy_scope(Vendor).listed
    end

    # GET /orders/vendors/1
    def show
    end

    # GET /orders/vendors/new
    def new
      @vendor = authorize Vendor.new(active: true)
    end

    # GET /orders/vendors/1/edit
    def edit
    end

    # GET /orders/vendors/pattern_test?url=...&pattern=...
    # What a pasted link gives: the vendor it matches and, with the given
    # pattern, the part number it pulls out.
    def pattern_test
      authorize Vendor, :create?
      probe = Vendor.new(part_number_pattern: params[:pattern])
      probe.validate
      @pattern_error = probe.errors[:part_number_pattern].first
      @url = params[:url].to_s.strip
      @matched_vendor = Vendor.for_url(@url) if @url.present?
      @part_number = probe.part_number_from(@url) unless @pattern_error
      render layout: false
    end

    # POST /orders/vendors
    def create
      @vendor = authorize Vendor.new(vendor_params)

      if @vendor.save
        redirect_to orders_vendor_path(@vendor), notice: "Vendor was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /orders/vendors/1
    def update
      if @vendor.update(vendor_params)
        redirect_to orders_vendor_path(@vendor), notice: "Vendor was successfully updated.", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /orders/vendors/1
    def destroy
      if @vendor.destroy
        redirect_to orders_vendors_path, notice: "Vendor was successfully deleted.", status: :see_other
      else
        redirect_to orders_vendor_path(@vendor), alert: "#{@vendor.name} has been used, so it can't be deleted. Untick In use instead.", status: :see_other
      end
    end

    private

    def set_vendor
      @vendor = authorize policy_scope(Vendor).find(params[:id])
    end

    def vendor_params
      permitted = params.require(:vendor).permit(:name, :website, :domains, :part_number_pattern, :account_note, :preferred, :active)
      permitted[:domains] = permitted[:domains].to_s.split(/[\s,]+/) if permitted.key?(:domains)
      permitted
    end
  end
end
