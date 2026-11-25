# Uploading a file source's records: Upload shows a preview of what would
# be added, changed and removed, and Apply replaces the records with the
# file's. Admins.
class Accounting::UploadsController < Accounting::BaseController
  MAX_BYTES = 2.megabytes

  before_action :set_source
  before_action :set_upload, only: %i[ show apply ]

  # GET /accounting/connections/:connection_id/uploads/new
  def new
  end

  # POST /accounting/connections/:connection_id/uploads
  def create
    file = params[:file]
    return refuse("Choose a CSV file to upload.") unless file.respond_to?(:read)
    return refuse("The file is too big: upload at most #{MAX_BYTES / 1.megabyte} MB.") if file.size > MAX_BYTES

    upload = @source.accounting_uploads.new(filename: file.original_filename.to_s.truncate(200), content: text(file.read), created_by: current_user.person)
    return refuse("The file is empty.") if upload.content.blank?

    upload.read_content.save!
    redirect_to accounting_connection_upload_path(@source, upload), status: :see_other
  end

  # GET /accounting/connections/:connection_id/uploads/:id
  def show
    @preview = Accounting::Files::Preview.new(@source, @upload)
  end

  # POST /accounting/connections/:connection_id/uploads/:id/apply
  def apply
    unless @upload.appliable?
      return redirect_to accounting_connection_upload_path(@source, @upload), alert: "This file can't be applied.", status: :see_other
    end

    @upload.update!(status: "applying", applied_by: current_user.person)
    Accounting::ApplyUploadJob.perform_later(@source, @upload)
    redirect_to accounting_connection_records_path(@source), notice: "Applying #{@upload.identifier_name}. The records show in a minute.", status: :see_other
  end

  # GET /accounting/connections/:connection_id/uploads/template
  def template
    send_data Accounting::Files::Template.csv, filename: "accounting-template.csv", type: "text/csv"
  end

  private
    def set_source
      @source = find_source(params[:connection_id])
      authorize @source, :upload?, policy_class: Accounting::SourcePolicy
    end

    def set_upload
      @upload = @source.accounting_uploads.find(params[:id])
    end

    def refuse(message)
      flash.now[:alert] = message
      render :new, status: :unprocessable_entity
    end

    # Spreadsheet programs save CSVs as UTF-8 or, on Windows, Windows-1252.
    def text(bytes)
      content = bytes.to_s.dup.force_encoding(Encoding::UTF_8)
      content.valid_encoding? ? content : content.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8)
    end
end
