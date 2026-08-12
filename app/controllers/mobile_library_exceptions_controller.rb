class MobileLibraryExceptionsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_mobile_library
  before_action :set_route
  before_action :set_exception, only: %i[edit update destroy]

  def new
    @exception = @route.mobile_library_exceptions.build(target_month: Date.today.beginning_of_month.next_month)
    set_form_options
  end

  def create
    @exception = @route.mobile_library_exceptions.build(exception_params)
    @exception.staff_ids_input = staff_ids_param
    if @exception.save
      sync_staffs
      redirect_to mobile_library_path(@mobile_library), notice: "例外を登録しました。"
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    @exception.staff_ids_input = staff_ids_param
    if @exception.update(exception_params)
      sync_staffs
      redirect_to mobile_library_path(@mobile_library), notice: "例外を更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @exception.destroy
    redirect_to mobile_library_path(@mobile_library), notice: "例外を削除しました。"
  end

  private

  def set_mobile_library
    @mobile_library = current_library.mobile_libraries.find(params[:mobile_library_id])
  end

  def set_route
    @route = @mobile_library.mobile_library_routes.find(params[:mobile_library_route_id])
  end

  def set_exception
    @exception = @route.mobile_library_exceptions.find(params[:id])
  end

  def set_form_options
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
  end

  def sync_staffs
    @exception.staffs = Staff.where(id: staff_ids_param.map(&:to_i))
  end

  def staff_ids_param
    Array(params.dig(:mobile_library_exception, :staff_ids)).reject(&:blank?)
  end

  def exception_params
    params.require(:mobile_library_exception).permit(:target_month, :date)
  end
end
