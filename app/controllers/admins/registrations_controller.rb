class Admins::RegistrationsController < Devise::RegistrationsController
  def create
    library_name = params.dig(:admin, :library_name).to_s.strip

    if library_name.blank?
      build_resource(sign_up_params)
      resource.errors.add(:base, "図書館名を入力してください")
      respond_with resource
      return
    end

    ActiveRecord::Base.transaction do
      library = Library.create!(name: library_name)
      build_resource(sign_up_params)
      resource.library = library
      resource.save!
      yield resource if block_given?

      if resource.persisted?
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        raise ActiveRecord::Rollback
      end
    end
  rescue ActiveRecord::RecordInvalid
    build_resource(sign_up_params)
    respond_with resource
  end

  private

  def sign_up_params
    params.require(:admin).permit(:email, :password, :password_confirmation)
  end
end
