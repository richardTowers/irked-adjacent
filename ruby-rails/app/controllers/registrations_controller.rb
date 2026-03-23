class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  before_action :redirect_if_authenticated

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      start_new_session_for @user
      redirect_to root_url, notice: "Welcome! Your account has been created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def redirect_if_authenticated
    redirect_to root_url if authenticated?
  end

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
