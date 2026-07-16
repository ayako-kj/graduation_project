class TemporaryClosedDatesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_temporary_closed_date, only: [:edit, :update, :destroy]

  def index
    @target_month = parse_target_month
    @temporary_closed_dates = current_library.temporary_closed_dates
                                             .for_month(@target_month)
                                             .ordered
    @temporary_closed_date = TemporaryClosedDate.new
  end

  def create
    @target_month = parse_target_month
    @temporary_closed_date = current_library.temporary_closed_dates.build(tcd_params)

    if @temporary_closed_date.save
      redirect_to temporary_closed_dates_path(month: @target_month.strftime("%Y-%m")),
                  notice: "臨時休館日「#{@temporary_closed_date.label}」を登録しました。"
    else
      @temporary_closed_dates = current_library.temporary_closed_dates.for_month(@target_month).ordered
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @target_month = parse_target_month
  end

  def update
    @target_month = parse_target_month
    if @temporary_closed_date.update(tcd_params)
      redirect_to temporary_closed_dates_path(month: @target_month.strftime("%Y-%m")),
                  notice: "臨時休館日を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    month = @temporary_closed_date.date.strftime("%Y-%m")
    @temporary_closed_date.destroy
    redirect_to temporary_closed_dates_path(month: month),
                notice: "臨時休館日を削除しました。"
  end

  private

  def set_temporary_closed_date
    @temporary_closed_date = current_library.temporary_closed_dates.find(params[:id])
  end

  def tcd_params
    params.require(:temporary_closed_date).permit(:date, :label)
  end

  def parse_target_month
    Date.parse("#{params[:month]}-01")
  rescue ArgumentError, TypeError
    Date.today.beginning_of_month
  end
end
