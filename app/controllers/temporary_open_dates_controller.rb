class TemporaryOpenDatesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_temporary_open_date, only: [:edit, :update, :destroy]

  def index
    @target_month = parse_target_month
    @temporary_open_dates = current_library.temporary_open_dates
                                           .for_month(@target_month)
                                           .ordered
    @temporary_open_date = TemporaryOpenDate.new
  end

  def create
    @target_month = parse_target_month
    @temporary_open_date = current_library.temporary_open_dates.build(tod_params)

    if @temporary_open_date.save
      redirect_to temporary_open_dates_path(month: @target_month.strftime("%Y-%m")),
                  notice: "臨時出勤日「#{@temporary_open_date.label}」を登録しました。"
    else
      @temporary_open_dates = current_library.temporary_open_dates.for_month(@target_month).ordered
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @target_month = parse_target_month
  end

  def update
    @target_month = parse_target_month
    if @temporary_open_date.update(tod_params)
      redirect_to temporary_open_dates_path(month: @target_month.strftime("%Y-%m")),
                  notice: "臨時出勤日を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    month = @temporary_open_date.date.strftime("%Y-%m")
    @temporary_open_date.destroy
    redirect_to temporary_open_dates_path(month: month),
                notice: "臨時出勤日を削除しました。"
  end

  private

  def set_temporary_open_date
    @temporary_open_date = current_library.temporary_open_dates.find(params[:id])
  end

  def tod_params
    params.require(:temporary_open_date).permit(:date, :label)
  end

  def parse_target_month
    Date.parse("#{params[:month]}-01")
  rescue ArgumentError, TypeError
    Date.today.beginning_of_month
  end
end
