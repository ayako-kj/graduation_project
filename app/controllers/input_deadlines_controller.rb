class InputDeadlinesController < ApplicationController
  before_action :authenticate_admin!

  def index
    @target_month = parse_target_month
    @input_deadline = current_library.input_deadlines.find_or_initialize_by(target_month: @target_month)
  end

  def save
    @target_month = parse_target_month
    @input_deadline = current_library.input_deadlines.find_or_initialize_by(target_month: @target_month)
    @input_deadline.deadline_on = params[:deadline_on].presence

    if @input_deadline.save
      redirect_to input_deadlines_path(month: @target_month.strftime("%Y-%m")),
                  notice: "#{@target_month.strftime('%Y年%-m月')}の入力締め切り日を保存しました。"
    else
      render :index, status: :unprocessable_entity
    end
  end

  private

  def parse_target_month
    Date.parse("#{params[:month]}-01")
  rescue ArgumentError, TypeError
    Date.today.beginning_of_month.next_month
  end
end
