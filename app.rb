require 'sinatra'
require 'httparty'
require 'json'
require 'redis'

post '/refbot' do
  # Logging
  puts "Processing request with params:"
  puts params.inspect

  $redis = Redis.new
  input = params[:text].to_s.split(' ')
  message = ""
  case input[0].downcase
  when 'hello'
    message = "Hello " + params[:user_name] + " welcome to referbot! Type /refbot help. for a list of all refbot keywords."
    notification = checklist
  when 'help'
    message = "This is a list off all the commands: /refbot hello, /refbot help, /refbot list, /refbot new, /refbot new candidate first-name last-name email phone vacancy"
    notification = checklist
  when 'list'
    message = getlist
    notification = checklist

  when "new"
    if !$redis.exists(params[:user_id])
      $redis.mapped_hmset(params[:user_id], {"candidate": {firstname: "", lastname: "", email: "", phone: "", vacancy: ""}, "step": "1"})
      message = params[:user_id] + " profile does not exist in the database. Created. Type '/refbot name <candidate name>' to start adding a new candidate."
    else
      message = params[:user_id] + " profile exists in the database. Type '/refbot name <candidate name>' to start adding a new candidate. Step 1/5."
    end

  when "reset"
    $redis.mapped_hmset(params[:user_id], {"candidate": {firstname: "", lastname: "", email: "", phone: "", vacancy: ""}, "step": "1"})
    message = "Candidate creation reset."

  when "name"
    $redis.mapped_hmset(params[:user_id], {"candidate": {name: input[1..-1].join(" "), email: "", phone: "", vacancy: ""}, "step": "2"})
    message = "New name: " + eval($redis.hmget(params[:user_id], "candidate")[0])[:name].to_s + ". \n Type '/refbot email <candidatee email>' yo add an email address. Step 2/5."

  when "email"
    if eval($redis.hmget(params[:user_id], "candidate")[0])[:name].to_s != ""
      $redis.mapped_hmset(params[:user_id], {"candidate": {name: eval($redis.hmget(params[:user_id], "candidate")[0])[:name].to_s, email: input[1..-1].join(" "), phone: "", vacancy: ""}, "step": "3"})
      message = "New email for " + eval($redis.hmget(params[:user_id], "candidate")[0])[:name].to_s + ": " + eval($redis.hmget(params[:user_id], "candidate")[0])[:email].to_s + ". \n Type '/refbot phone <candidate phone>' to add a phone number. Step 3/5."
    else
      message = "First add a name using '/refbot name <candidate name>'"
    end

  when "phone"
    if eval($redis.hmget(params[:user_id], "candidate")[0])[:name].to_s != ""
      $redis.mapped_hmset(params[:user_id], {"candidate": {name: eval($redis.hmget(params[:user_id], "candidate")[0])[:name].to_s, email: eval($redis.hmget(params[:user_id], "candidate")[0])[:email].to_s, phone: input[1..-1].join(" "), vacancy: ""}, "step": "3"})
      message = "New phone number for " + eval($redis.hmget(params[:user_id], "candidate")[0])[:name].to_s + ": " + eval($redis.hmget(params[:user_id], "candidate")[0])[:phone].to_s + ". \n Type '/refbot CV <candidate CV URL>' to add a CV URL. Step 4/5."
    else
      message = "First add a name using '/refbot name <candidate name>'"
    end
  end

  # if input[0].downcase == "new"
  #   redis.hmset(input[1], "firstname", input[2], "lastname", input[3], "email", input[4], "phone", input[5], "vacancy", input[6])
  #   # postback redis.hmget(input[1], "firstname", "lastname", "email", "phone", "vacancy").to_s, params[:channel_id], params[:user_name]
  #
  #   url = "https://api.recruitee.com/c/referbot/careers/offers/#{redis.hmget(input[1], "vacancy")[0].to_s}/candidates.json"
  #   candidate = {
  #     name: redis.hmget(input[1], "firstname")[0].to_s + " " + redis.hmget(input[1], "lastname")[0].to_s,
  #     email: redis.hmget(input[1], "email")[0].to_s,
  #     phone: redis.hmget(input[1], "phone")[0].to_s,
  #     remote_cv_url: "http://cd.sseu.re/welcome-pdf.pdf"
  #   }
  #
  #   HTTParty.post(url,
  #     body: { candidate: candidate }.to_json,
  #     headers: { "content-type" => "application/json" })
  #
  #     postback params[:user_name].to_s + " has just refered a new candidate for the following vacancy: https://referbot.recruitee.com/o/#{redis.hmget(input[1], "vacancy")[0].to_s}", params[:channel_id], params[:user_name]
  #
  #   status 200
  # end

  json_message = {"text" => message, params[:user_name] => "refbot", "channel" => params[:channel_id]}
  if ENV['DEV_ENV'] == 'test'
    content_type :json
   json_message[:text] = "#{message} + #{notification}"
   json_message.to_json
  else
    slack_webhook = ENV['SLACK_WEBHOOK_URL']
    notif_message = {"text" => notification, params[:user_name] => "refbot", "channel" => params[:channel_id]}
    HTTParty.post slack_webhook, body: json_message.to_json, headers: {'content-type' => 'application/json'}
    HTTParty.post slack_webhook, body: notif_message.to_json, headers: {'content-type' => 'application/json'}
  end
end

def getlist
  receivelist = HTTParty.get('https://api.recruitee.com/c/referbot/careers/offers').to_json
  # receivelist = HTTParty.get('https://api.recruitee.com/c/levelupventures/careers/offers').to_json
  test1 = JSON.parse(receivelist, symbolize_names: true)
  contents = test1[:offers]
  message = ""
  contents.each do |content|
    message = message + "#{content[:id]}, #{content[:title]} \n #{content[:careers_url]} \n"
  end
  return message;
end

def checklist
  check_list = HTTParty.get('https://api.recruitee.com/c/referbot/careers/offers').to_json
  test1 = JSON.parse(check_list, symbolize_names: true)
  contents = test1[:offers]
  message = ""
  if $redis.get('lists') != contents.size.to_s
    message = 'vacancy list has been updated'
    $redis.set('lists', contents.size.to_s)
  end
  #message = $redis.get("listsize")
  return message
end
