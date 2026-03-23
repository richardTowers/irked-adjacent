module AuthenticationHelpers
  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123!" }
  end

  def create_and_sign_in_user(email: "test@example.com", password: "password123!")
    user = User.create!(email_address: email, password: password, password_confirmation: password)
    sign_in_as(user)
    user
  end
end
