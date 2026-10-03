class PersonFieldsController < InternalController
  Preview = Struct.new(:viewer_id, :subject_id)

  before_action :set_person_field, only: %i[ show edit update destroy move archive restore ]
  before_action :require_feature, only: %i[ new create roster ]

  # GET /person_fields
  def index
    authorize PersonField
    scope = policy_scope(PersonField)
    scope = scope.system unless feature_enabled?
    scope = scope.active unless params[:archived] == "1"
    @person_fields = scope.ordered.includes(:team, :person_field_group, person_field_badge_grants: :badge)
    @guardianship_configured = RelationshipType.guardianship_configured?
  end

  # GET /person_fields/1
  def show
  end

  # GET /person_fields/new
  def new
    @person_field = authorize PersonField.new(read_permission: :admin, write_permission: :admin)
  end

  # GET /person_fields/1/edit
  def edit
  end

  # POST /person_fields
  def create
    @person_field = authorize PersonField.new(person_field_params)

    if @person_field.save
      redirect_to person_fields_path, notice: "Person field was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /person_fields/1
  def update
    if @person_field.update(person_field_params)
      redirect_to person_fields_path, notice: "Person field was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /person_fields/1
  def destroy
    count = @person_field.person_field_values.count
    @person_field.destroy!
    redirect_to person_fields_path(archived: "1"), notice: "Person field was deleted along with #{helpers.pluralize(count, "value")}.", status: :see_other
  end

  # PATCH /person_fields/1/move
  def move
    @person_field.move(params[:direction])
    redirect_to person_fields_path, status: :see_other
  end

  # PATCH /person_fields/1/archive
  def archive
    @person_field.archive!
    redirect_to person_fields_path, notice: "Person field was archived. Its values are kept.", status: :see_other
  end

  # PATCH /person_fields/1/restore
  def restore
    @person_field.restore!
    redirect_to person_fields_path, notice: "Person field was restored.", status: :see_other
  end

  # GET /person_fields/preview
  def preview
    authorize PersonField, :preview?
    @preview = Preview.new(params.dig(:preview, :viewer_id), params.dig(:preview, :subject_id))
    @viewer = Person.find_by(id: @preview.viewer_id) if @preview.viewer_id.present?
    @subject = Person.find_by(id: @preview.subject_id) if @preview.subject_id.present?
    return unless @viewer && @subject

    access = PersonFieldAccess.new(@viewer, @subject)
    @rows = PersonField.in_use.ordered.includes(person_field_badge_grants: :badge).filter_map do |field|
      next unless access.applies?(field)
      { field: field, read: access.access(field, :read), write: access.access(field, :write) }
    end
  end

  # GET /person_fields/roster
  def roster
    authorize PersonField, :roster?
    viewer = current_user.person
    @fields = policy(PersonField).readable_fields
    @teams = policy_scope(Team).order(:name)
    @selected = @fields.select { |field| Array(params[:field_ids]).include?(field.id) }
    return if @selected.empty?

    people = policy_scope(Person)
    people = people.where(id: Team.find(params[:team_id]).descendant_people.select(:id)) if params[:team_id].present?
    @readable = @selected.to_h { |field| [ field.id, field.readable_subjects_for(viewer).where(id: people.select(:id)).ids.to_set ] }
    @people = Person.where(id: @readable.values.reduce(:|).to_a).order(:last_name, :first_name)
    @rows = PersonFieldValue.where(person_id: @people.select(:id), person_field_id: @selected.map(&:id)).index_by { |row| [ row.person_id, row.person_field_id ] }
  end

  private
    def set_person_field
      @person_field = authorize policy_scope(PersonField).find(params[:id])
    end

    def feature_enabled?
      GatherPack::Features.enabled?(:person_fields)
    end

    def require_feature
      redirect_to root_path, notice: "Custom person fields are turned off" unless feature_enabled?
    end

    def person_field_params
      permitted = [ :name, :help_text, :read_permission, :write_permission, :person_field_group_id, :position,
        :required, :show_on_profile, :team_id, :choices_text, :min, :max, :pattern, :pattern_hint, badge_access: {} ]
      permitted += [ :key ] if @person_field.nil? || @person_field.new_record?
      permitted += [ :data_type ] if @person_field.nil? || @person_field.person_field_values.none?
      params.require(:person_field).permit(*permitted)
    end
end
