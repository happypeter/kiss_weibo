# encoding: utf-8

require 'weibo_2'
require 'time_ago_in_words'
require 'sinatra/reloader'
require 'sinatra'
require "sinatra/config_file"

config_file 'config.yml'

log = File.new("logs/sinatra.log", "a")
STDOUT.reopen(log)
STDERR.reopen(log)

%w(rubygems bundler).each { |dependency| require dependency }
Bundler.setup
%w(sinatra haml sass).each { |dependency| require dependency }
enable :sessions

WeiboOAuth2::Config.api_key = settings.api_key
WeiboOAuth2::Config.api_secret = settings.api_secret
WeiboOAuth2::Config.redirect_uri = settings.redirect_uri

use Rack::Auth::Basic, "Restricted Area" do |username, password|
  username == settings.username and password == settings.password
end

get '/episodes/:id' do
  response = RestClient.get "happycasts.net/episodes/#{params[:id]}.json"
  response_hash = MultiJson.load(response)
  @status_body = status_body(response_hash)
  @poster_link = poster_link(response_hash)
  @episode_id = params[:id]
  client = WeiboOAuth2::Client.new
  client.get_token_from_hash({:access_token => session[:access_token], :expires_at => session[:expires_at]})
  @user = client.users.show_by_uid(session[:uid])
  haml :show
end

get '/post_status/:id' do
  response = RestClient.get "happycasts.net/episodes/#{params[:id]}.json"
  response_hash = MultiJson.load(response)
  status_body = status_body(response_hash)
  local_poster_link = local_poster_link(response_hash)

  client = WeiboOAuth2::Client.new
  client.get_token_from_hash({:access_token => session[:access_token], :expires_at => session[:expires_at]})
  statuses = client.statuses

  pic = File.open(local_poster_link)
  # pic = File.open("/home/peter/media/assets/episodes/stills/002-snipmate.png")
  statuses.upload(status_body, pic)

  redirect '/'
end

get '/' do
  client = WeiboOAuth2::Client.new
  if session[:access_token] && !client.authorized?
    token = client.get_token_from_hash({:access_token => session[:access_token], :expires_at => session[:expires_at]}) 
    p "*" * 80 + "validated"
    p token.inspect
    p token.validated?

    unless token.validated?
      reset_session
      redirect '/connect'
      return
    end
  end
  if session[:uid]
    @user = client.users.show_by_uid(session[:uid]) 
    @statuses = client.statuses
  end
  haml :index
end

get '/connect' do
  client = WeiboOAuth2::Client.new
  redirect client.authorize_url
end

get '/callback' do
  client = WeiboOAuth2::Client.new
  access_token = client.auth_code.get_token(params[:code].to_s)
  session[:uid] = access_token.params["uid"]
  session[:access_token] = access_token.token
  session[:expires_at] = access_token.expires_at
  p "*" * 80 + "callback"
  p access_token.inspect
  @user = client.users.show_by_uid(session[:uid].to_i)
  redirect '/'
end

get '/logout' do
  reset_session
  redirect '/'
end 

get '/screen.css' do
  content_type 'text/css'
  sass :screen
end

post '/update' do
  client = WeiboOAuth2::Client.new
  client.get_token_from_hash({:access_token => session[:access_token], :expires_at => session[:expires_at]}) 
  statuses = client.statuses

  unless params[:file] && (tmpfile = params[:file][:tempfile]) && (name = params[:file][:filename])
    statuses.update(params[:status])
  else
    status = params[:status] || '图片'
    pic = File.open(tmpfile.path)
    statuses.upload(status, pic)
  end

  redirect '/'
end

helpers do
  def status_body(response_hash)
    id = response_hash['episode']['id'].to_s
    name = response_hash['episode']['name']
    link = "http://happycasts.net/episodes/" + id
    des = response_hash['episode']['description']
    id + '期 ' + name + " " + link + " " + des
  end
  def poster_link(response_hash)
    name = response_hash['episode']['name']
    id = response_hash['episode']['id'].to_s
    asset = [id.rjust(3, "0"), name].join("-") + ".png"
    "http://media.happycasts.net/assets/episodes/stills/#{asset}"
  end
  def local_poster_link(response_hash)
    name = response_hash['episode']['name']
    id = response_hash['episode']['id'].to_s
    asset = [id.rjust(3, "0"), name].join("-") + ".png"
    "/home/peter/media/assets/episodes/stills/#{asset}"
  end
  def reset_session
    session[:uid] = nil
    session[:access_token] = nil
    session[:expires_at] = nil
  end
end
