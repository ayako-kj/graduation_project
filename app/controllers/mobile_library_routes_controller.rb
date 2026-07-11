class MobileLibraryRoutesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_mobile_library
  before_action :set_route, only: %i[edit update destroy]

  def new
    @route = @mobile_library.mobile_library_routes.build
    set_form_options
  end

  def create
    @route = @mobile_library.mobile_library_routes.build(route_params)
    if @route.save
      update_staffs(@route)
      redirect_to mobile_library_path(@mobile_library), notice: "コースを登録しました。"
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    if @route.update(route_params)
      update_staffs(@route)
      redirect_to mobile_library_path(@mobile_library), notice: "コースを更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @route.name
    @route.destroy
    redirect_to mobile_library_path(@mobile_library), notice: "#{name}を削除しました。"
  end

  private

  def set_mobile_library
    @mobile_library = current_library.mobile_libraries.find(params[:mobile_library_id])
  end

  def set_route
    @route = @mobile_library.mobile_library_routes.find(params[:id])
  end

  def set_form_options
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
  end

  def update_staffs(route)
    ids = params.dig(:mobile_library_route, :staff_ids)&.reject(&:blank?)&.map(&:to_i) || []
    route.staffs = current_library.staffs.where(id: ids)
  end

  def route_params
    params.require(:mobile_library_route).permit(:name, :wday, :week_number)
  end
end
