class StaffsController < ApplicationController
  before_action :authenticate_admin!

  def index
    @staffs = Staff.includes(:staff_type, :employment_type).order(:id)
  end
end
