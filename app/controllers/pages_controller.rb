class PagesController < ApplicationController
  def about
    render "about"
  end

  def error_404
    render status: 404
  end
end
