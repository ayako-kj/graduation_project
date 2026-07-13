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

  def update
    library_name = params.dig(:admin, :library_name).to_s.strip
    self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)

    new_email    = params.dig(:admin, :email).to_s.strip
    new_password = params.dig(:admin, :password).to_s
    credential_changed = new_email != resource.email || new_password.present?

    if credential_changed
      resource_updated = update_resource(resource, account_update_params)
    else
      resource_updated = true
    end

    if resource_updated
      library_attrs = {}
      library_attrs[:name]                = library_name if library_name.present?
      raw_wday = params.dig(:admin, :regular_closed_wday)
      library_attrs[:regular_closed_wday] = raw_wday.present? ? raw_wday.to_i : nil
      current_library.update(library_attrs)
      bypass_sign_in(resource) if credential_changed
      redirect_to edit_admin_registration_path, notice: "アカウント情報を更新しました。"
    else
      clean_up_passwords resource
      set_minimum_password_length
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    library = current_library
    resource.destroy
    library&.destroy
    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    redirect_to root_path, notice: "アカウントを削除しました。"
  end

  private

  def sign_up_params
    params.require(:admin).permit(:email, :password, :password_confirmation)
  end

  def account_update_params
    params.require(:admin).permit(:email, :password, :password_confirmation, :current_password)
  end
end
