class API::V1::SuggestController < ApplicationController
  def show
    keyword = params[:suggest_query] # TODO use strong params
    return if keyword.empty?
    suggestions = SolrRequests.new(keyword).get_suggestions
    if suggestions.empty?
      render json: { message: 'no suggestions found' }, status: 404
    else
      render json: { suggestions: suggestions }, status: 200
    end
  end
end