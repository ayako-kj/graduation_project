class SpecialDatesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_special_date, only: %i[edit update destroy]

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

  def edit
  end

  def update
    if @special_date.update(special_date_params)
      redirect_to special_dates_path, notice: "特定日を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @special_date.destroy
    redirect_to special_dates_path, notice: "#{@special_date.label}を削除しました。"
  end

  private

  def set_special_date
    @special_date = SpecialDate.find(params[:id])
  end

  def special_date_params
    params.require(:special_date).permit(:date, :label, :target_group)
  end
end
