class Admins::RegistrationsController < Devise::RegistrationsController
  def create
    library_name = params.dig(:admin, :library_name).to_s.strip

    build_resource(sign_up_params)

    if library_name.blank?
      resource.errors.add(:base, "図書館名を入力してください")
      render :new, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      library = Library.create!(name: library_name)
      resource.library = library
      resource.save!
      yield resource if block_given?

      if resource.persisted?
        sign_up(resource_name, resource)
        redirect_to after_sign_up_path_for(resource), notice: "アカウントを登録しました。"
      else
        raise ActiveRecord::Rollback
      end
    end
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private

  def sign_up_params
    params.require(:admin).permit(:email, :password, :password_confirmation)
  end
end
