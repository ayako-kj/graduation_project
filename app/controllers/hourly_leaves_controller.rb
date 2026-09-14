class HourlyLeavesController < ApplicationController
  before_action :authenticate_admin!

  def destroy
    hourly_leave = HourlyLeave.where(staff: current_library.staffs).find(params[:id])
    month = hourly_leave.date.strftime("%Y-%m")
    staff_name = hourly_leave.staff.name
    date_label = hourly_leave.date.strftime("%-m月%-d日")
    hourly_leave.destroy

    tab = params[:from] == "by-staff" ? "by-staff" : nil
    redirect_to leave_requests_path(month: month, tab: tab), notice: "#{staff_name}の#{date_label}の時間休を削除しました。"
  end
end
