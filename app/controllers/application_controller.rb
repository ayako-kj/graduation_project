class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :current_library

  private

  def current_library
    @current_library ||= current_admin&.library
  end

  def after_sign_in_path_for(resource)
    root_path
  end

  def after_sign_out_path_for(resource_or_scope)
    root_path
  end
end
