# Membership intake (feature :intake): public registration pages under
# /join, staff screens under /registrations. Fixed paths before :slug.
scope "/join", module: :intake, as: :intake do
  get "verify" => "verifications#show", :as => :verification
  post "verify" => "verifications#create"
  get "guardian" => "guardian_confirmations#show", :as => :guardian_confirmation
  post "guardian" => "guardian_confirmations#create"
  get "email" => "email_changes#show", :as => :email_change
  post "email" => "email_changes#create"
  get ":slug" => "join#show", :as => :join
  post ":slug" => "join#create"
  get ":slug/me" => "me#show", :as => :me
  patch ":slug/me/people/:person_id" => "me#update_person", :as => :me_person
  post ":slug/me/guardians" => "me#add_guardian", :as => :me_guardians
  post ":slug/me/members" => "me#add_member", :as => :me_members
  post ":slug/me/email" => "me#change_email", :as => :me_email
  delete ":slug/me/applications/:id" => "me#withdraw", :as => :me_application
  get ":slug/kiosk" => "kiosk#show", :as => :kiosk
  post ":slug/kiosk" => "kiosk#create"
end
scope module: :intake, as: :intake do
  resources :spam_people, only: %i[show destroy], path: "registration-spam"
  resources :registrations do
    member do
      get :copy
      get :waiting
      patch :close
      delete :entries, action: :destroy_entries
    end
    resources :entries, only: [] do
      post :resend, on: :member
    end
    resources :matches, only: [] do
      member do
        post :link
        post :keep_separate
      end
    end
    resources :guardians, only: %i[create update] do
      post :resend, on: :member
    end
  end
  resources :teams, only: [] do
    resources :registrations, only: %i[index new]
  end
end
