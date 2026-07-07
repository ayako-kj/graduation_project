class SpecialDatesController < ApplicationController
  before_action :authenticate_admin!

  TARGET_GROUPS = %w[全職員 正規職員 専門司書 司書 行政職 一般事務].freeze

  def index
    @special_dates = SpecialDate.order(:date)
  end

  def new
    @special_date = SpecialDate.new
  end

  def create
    @special_date = SpecialDate.new(special_date_params)
    if @special_date.save
      redirect_to special_dates_path, notice: "特定日を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def special_date_params
    params.require(:special_date).permit(:date, :label, :target_group)
  end
end
