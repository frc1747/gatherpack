class UsersController < InternalController
  before_action :set_person
  before_action :set_user, only: %i[ edit update ]
  before_action :build_user, only: %i[ new create ]

  def new
  end

  # Always a new login: an existing User is never adopted by email, so a taken
  # email fails the uniqueness validation instead.
  def create
    @user.assign_attributes(user_params)

    if @user.save
      @person.update(user: @user)
      redirect_to @person, notice: "User information was successfully updated.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @user.acting_user = current_user
    if @user.update(user_params)
      redirect_to @person, notice: "User information was successfully updated.", status: :see_other
      if current_user == @user
        bypass_sign_in @user
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    # Finding the person only needs them to be visible; the login itself is
    # authorized against UserPolicy.
    def set_person
      @person = authorize policy_scope(Person).find(params[:person_id]), :show?
    end

    def set_user
      @user = authorize @person.user
    end

    # A person has at most one login; replacing it is not something new/create
    # does. Changing an existing login goes through edit/update.
    def build_user
      if @person.user
        authorize User.new
        redirect_to @person, notice: "This person already has a login.", status: :see_other
      else
        @user = authorize User.new(person: @person)
      end
    end

    def user_params
      fields = [ :email, :password, :password_confirmation, :person_id, :old_password ]
      fields << :admin if current_user.admin?
      fields << :architect if current_user.architect?
      params.require(:user).permit(*fields)
    end
end
