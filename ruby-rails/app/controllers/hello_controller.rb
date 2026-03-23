class HelloController < ApplicationController
  allow_unauthenticated_access

  def index
    render plain: "Hello, world!"
  end
end
