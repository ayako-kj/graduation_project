class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :current_library
  before_action :require_library!

  private

  def current_library
    @current_library ||= current_admin&.library
  end

  def require_library!
    return unless admin_signed_in?
    return if current_library.present?

    sign_out current_admin
    redirect_to new_admin_session_path, alert: "アカウントに図書館が紐付いていません。再度ログインするか、新規登録を行ってください。"
  end

  def after_sign_in_path_for(resource)
    root_path
  end

  def after_sign_out_path_for(resource_or_scope)
    root_path
  end

  def temporary_closed_dates_map(library, target_month)
    TemporaryClosedDate
      .where(library: library, date: target_month.beginning_of_month..target_month.end_of_month)
      .each_with_object({}) { |tcd, h| h[tcd.date] = tcd.label.presence || "臨時休館日" }
  end
end
