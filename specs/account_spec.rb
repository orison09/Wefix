# frozen_string_literal: true

require_relative './spec_helper'
require 'json'

describe 'Test Document Handling' do
  include Rack::Test::Methods

  before do
    wipe_database
    @req_header = { 'CONTENT_TYPE' => 'application/json' }
  end

  describe 'Account information' do
    it 'HAPPY: should be able to get details of a single account' do
      account_data = DATA[:accounts][1]
      account = Wefix::EmailAccount.create(account_data)

      credentials = {
        username: account_data['username'],
        password: account_data['password']
      }

      auth_account = Wefix::AuthenticateEmailAccount.call(credentials).to_json
      @data_user = JSON.parse(auth_account)

      header 'AUTHORIZATION', "Bearer #{@data_user['auth_token']}"
      get "/api/v1/accounts/#{account.username}"

      _(last_response.status).must_equal 200

      result = JSON.parse last_response.body
      _(result['username']).must_equal account.username
      _(result['salt']).must_be_nil
      _(result['password']).must_be_nil
      _(result['password_hash']).must_be_nil
    end
  end

  describe 'Account Creation' do
    before do
      @account_data = DATA[:accounts][1]
    end

    it 'HAPPY: should be able to create new email accounts' do
      post 'api/v1/accounts', @account_data.to_json, @req_header
      _(last_response.status).must_equal 201
      _(last_response.header['Location'].size).must_be :>, 0

      created = JSON.parse(last_response.body)['data']
      account = Wefix::EmailAccount.first

      _(created['username']).must_equal @account_data['username']
      _(created['email']).must_equal @account_data['email']
      _(account.password?(@account_data['password'])).must_equal true
      _(account.password?('not_really_the_password')).must_equal false
    end

    it 'BAD: should not create account with illegal attributes' do
      bad_data = @account_data.clone
      bad_data['created_at'] = '1900-01-01'
      post 'api/v1/accounts', bad_data.to_json, @req_header

      _(last_response.status).must_equal 400
      _(last_response.header['Location']).must_be_nil
    end
  end

  describe 'Account Authentication' do
    before do
      @account_data = DATA[:accounts][1]
      @account = Wefix::EmailAccount.create(@account_data)
    end

    it 'HAPPY: should authenticate email valid credentials' do
      credentials = { username: @account_data['username'],
                      password: @account_data['password'] }

      signed_data = SignedRequest
                    .new(Wefix::Api.config)
                    .sign(credentials)
      post 'api/v1/auth/authenticate/email_account', signed_data.to_json

      _(last_response.status).must_equal 200
      auth_account = JSON.parse(last_response.body)
      _(last_response.status).must_equal 200
      account_response = auth_account['account']
      _(account_response['username'].must_equal(@account_data['username']))
      _(account_response['email'].must_equal(@account_data['email']))
      _(account_response['id'].must_be_nil)
    end

    it 'BAD: should not authenticate invalid password' do
      credentials = { username: @account_data['username'],
                      password: 'fakepassword' }

      signed_data = SignedRequest
                    .new(Wefix::Api.config)
                    .sign(credentials)

      post 'api/v1/auth/authenticate/email_account', signed_data.to_json

      result = JSON.parse(last_response.body)

      _(last_response.status).must_equal 403
      _(result['message']).wont_be_nil
      _(result['username']).must_be_nil
      _(result['email']).must_be_nil
    end
  end
end
