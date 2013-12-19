require 'map'

class Hash
  def recursive_symbolize_keys!
    symbolize_keys!
    # symbolize each hash in .values
    values.each{|h| h.recursive_symbolize_keys! if h.is_a?(Hash) }
    # symbolize each hash inside an array in .values
    values.select{|v| v.is_a?(Array) }.flatten.each{|h| h.recursive_symbolize_keys! if h.is_a?(Hash) }
    self
  end
end

class ServeController < ApplicationController
  layout false
  respond_to :json
  before_action :default_format_json
  skip_before_filter :verify_authenticity_token  
    
  def get    
    c, @json = validate_bucket_connection(params)
    return unless @json    
    
    doc, flags, cas = c.get(params[:key], :extended => true)

    if doc
      @json.code = 200
      @json.success = true
      @json.messages << "Key found"
      @json.document = doc
      @json.extra_info = {
        cas: cas,
        data_type: guess_data_type(doc)
      }
    else
      @json.code = 404
      @json.success = false
      @json.messages << "Key [#{params[:key]}] not found"
      @json.error_message = "ERROR: Key not found"
    end
  
    render json: @json
  end

  def set

    c, @json = validate_bucket_connection(params)
    return unless @json        
    
    begin
      @json.messages << "Will set expiration to #{params[:post][:options][:ttl]} seconds" if params[:post][:options][:ttl]        
      
      cas = c.set(params[:key], params[:post][:value], params[:post][:options])      
      @json.code = 200
      @json.success = true
      @json.messages << "Set completed"
      @json.result_data = {
        cas: cas
      }      
    rescue  Couchbase::Error::KeyExists
      doc, f, ecas = c.get(params[:key], extended: true)

      @json.code = 403
      @json.success = false
      @json.messages << "Provided CAS and document CAS did not match, so cannot set"
      @json.error_message = "ERROR: CAS mismatch"

      @json.extra_info = {
        provided_cas: params[:post][:options][:cas],
        expected_cas: ecas
      }      
    end
    
    render json: @json
  end

  def add
    c, @json = validate_bucket_connection(params)
    return unless @json        
    pp params
    begin
      @json.messages << "Will add with expiration of #{params[:post][:options][:ttl]} seconds" if params[:post][:options][:ttl]        
      
      cas = c.add(params[:key], params[:post][:value], params[:post][:options])

      @json.code = 200
      @json.success = true
      @json.messages << "Add completed"
      @json.result_data = {
        cas: cas
      }
    rescue Couchbase::Error::KeyExists
      
      @json.code = 403
      @json.success = false
      @json.messages << "Key exists already"
      @json.error_message = "ERROR: Key already exists, cannot add"
    end
    
    render json: @json
  end

  def replace
    c, @json = validate_bucket_connection(params)
    return unless @json        
    
    #p params
    #p params.symbolize_keys
    
    begin
      @json.messages << "Will replace expiration with #{params[:post][:options][:ttl]} seconds" if params[:post][:options][:ttl]        
      
      cas = c.replace(params[:key], params[:post][:value], params[:post][:options].symbolize_keys)

      @json.code = 200
      @json.success = true
      @json.messages << "Replace completed"
      @json.result_data = {
        cas: cas
      }
    rescue Couchbase::Error::NotFound
      
      @json.code = 404
      @json.success = false
      @json.messages << "Key not found, replace failed"
      @json.error_message = "ERROR: Expected key not found, cannot replace"
      
    rescue Couchbase::Error::KeyExists
      
      doc, f, ecas = c.get(params[:key], extended: true)
      
      @json.code = 403
      @json.success = false
      @json.messages << "Provided CAS and document CAS did not match, so cannot replace"
      @json.error_message = "ERROR: CAS mismatch"
      
      @json.extra_info = {
        provided_cas: params[:post][:options][:cas],
        expected_cas: ecas
      }
      
    end
    
    render json: @json
  end

  # def test
  #     @json = {}
  #     
  #     case params[:op]
  #       
  #     when "set"
  #       p = {
  #         bucket: "default",
  #         key: "jasdeep",
  #         post: {
  #           value: {
  #             name: "Jasdep Jaitla",
  #             email: "jasdeep@jasdeep.com",
  #             username: "scalabl3"
  #           },
  #           options: {
  #             #ttl: 20
  #           }
  #         }
  #       }
  #       @json = set(p)
  #     when "replace"
  #       p = {
  #         bucket: "default",
  #         key: "jasdeep",
  #         post: {
  #           value: {
  #             name: "Jasdep Jaitla",
  #             email: "jasdeep@jasdeep.com",
  #             username: "scalabl3",
  #             dob: "1975/07/09"
  #           },
  #           options: {
  #             #ttl: 20
  #             cas: 683187286743056384
  #           }
  #         }
  #       }
  #       @json = replace(p)
  #     when "add"
  #       p = {
  #         bucket: "default",
  #         key: Time.now.to_i.to_s,
  #         post: {
  #           value: {
  #             name: "Jasdep Jaitla",
  #             email: "jasdeep@jasdeep.com",
  #             username: "scalabl3",
  #             dob: "1975/07/09",
  #             created_at: Time.now.to_i
  #           },
  #           options: {
  #             ttl: 20
  #             
  #           }
  #         }
  #       }
  #       @json = add(p)
  #     end
  #     
  #     render json: @json
  #   end
  
  def incr
    c, @json = validate_bucket_connection(params)
    return unless @json
    
    if params[:create]
      @json.messages << "If key is null, Counter will be created and return 0"
    end

    begin
      doc, cas = c.incr(params[:key], params[:amount].to_i, { extended: true, delta: params[:amount].to_i, create: params[:create]})      
          
      if doc
        @json.code = 200
        @json.success = true
        if doc == 0
          @json.messages << "Counter created and initialized to 0"
        else
          @json.messages << "Counter incremented by #{params[:amount]}"
        end
        @json.result_data = {
          cas: cas,
          value: doc
        }        
      else
        @json.code = 204
        @json.success = false
        @json.messages << "Key not found"
        @json.error_message = "ERROR: Key not found"
      end
    rescue Couchbase::Error::DeltaBadval
      @json.code = 204
      @json.success = false
      @json.messages << "Stored value not an Integer, cannot increment"
      @json.error_message = "ERROR: Stored value is not an Integer"
      
      doc, flags, cas = c.get(params[:key], extended: true)
      @json.extra_info = {
        cas: cas,
        stored_data_type: guess_data_type(doc)
      }
    end
    
    render json: @json
  end
  
  def decr
    c, @json = validate_bucket_connection(params)
    return unless @json
    
    if params[:create]
      @json.messages << "If key is null, Counter will be created and return 0"
    end
    
    begin
      doc, cas = c.decr(params[:key], params[:amount].to_i, { extended: true, delta: params[:amount].to_i, create: params[:create]}) 
    
      if doc
        @json.code = 200
        @json.success = true
        if doc == 0 && create
          @json.messages << "Counter created at 0, or decremented to 0"
          @json.messages << "WARN: cannot decrement atomic counters == 0, will remain 0"
        elsif doc == 0
          @json.messages << "Counter decremented to 0"
          @json.messages << "WARN: cannot decrement atomic counters == 0, will remain 0"
        else
          @json.messages << "Counter decremented by #{params[:amount]}"
        end
        @json.result_data = {
          cas: cas,
          value: doc
        }
      else
        @json.code = 204
        @json.success = false
        @json.messages << "Key not found"
        @json.error_message = "ERROR: Key not found"
      end
    rescue Couchbase::Error::DeltaBadval      
      @json.code = 204
      @json.success = false
      @json.messages << "Stored value not an Integer, cannot decrement"
      @json.error_message = "ERROR: Stored value is not an Integer"
      
      doc, flags, cas = c.get(params[:key], extended: true)
      @json.extra_info = {
        cas: cas,
        stored_data_type: guess_data_type(doc)
      } 
    end
    
    render json: @json
  end
  
  def delete
    c, @json = validate_bucket_connection(params)
    return unless @json
    
    begin
      c.delete(params[:key], quiet: false)
      @json.code = 200
      @json.success = true
      @json.messages << "Key-Value Deleted for [#{params[:key]}]"
      
    rescue Couchbase::Error::NotFound
      @json.code = 204
      @json.success = false
      @json.messages << "Key not found, couldn't delete"
      @json.error_message = "ERROR: Key not found"
    end
    
    render json: @json
  end
  
  def ddocs
    c, @json = validate_bucket_connection(params)
    return unless @json
    
    @json.code = 200
    @json.success = true
    @json.operation.environment = c.environment
    
    if params[:all]
      @json.messages << "Design Documents for all buckets requested"
      @json.ddocs = Map.new
      
      $cb.connections.each_pair do |b, c|
        @json.ddocs[b] = c.design_docs
        @json.messages << "Design Documents retrieved for bucket [#{b}]"
      end
      
    else
      @json.ddocs = c.design_docs
      @json.messages << "Design Documents retrieved for bucket [#{c.bucket}]"
    end
    
    render json: @json
  end
  
  def view_query
    c, @json = validate_bucket_connection(params)
    return unless @json
    
    @json.messages << "Bucket [#{c.bucket}] Design Document [#{params[:ddoc]}] View Query [#{params[:view]}] requested"
    
    unless c.design_docs.include? params[:ddoc]
      @json.code = 404
      @json.success = false
      @json.messages << "Design Document not found"
      @json.error_message = "ERROR: Design Document doesn't exist"
      
      render json: @json and return
    end
    
    unless c.design_docs[params[:ddoc]].views.include? params[:view]
      @json.code = 404
      @json.success = false
      @json.messages << "View not found"
      @json.error_message = "ERROR: View doesn't exist"
      
      render json: @json and return
    end
    
    #c.design_docs[params[:ddoc]].views.each do |v|
    #  @json.views << v.class.to_s
    #end
    query_params = { 
      include_docs: false,
      reduce: false, 
      limit: 10,
      descending: false,
      group: false,
      stale: :update_after,
      quiet: true,
      group: false }

    @json.extra_info = {}
    @json.extra_info.query_defaults = query_params
    
    if params[:post] and params[:post][:options]
      @json.operation.query_params = query_params.merge!(params[:post][:options].symbolize_keys).recursive_symbolize_keys!
      @json.operation.query_params.stale = false if @json.operation.query_params.stale == "false" 
    else      
      @json.operation.query_params = query_params      
    end
    
    if request.method.upcase == "GET"
      @json.messages << "GET operation used, will use query_defaults"
    elsif request.method.upcase == "POST"
      @json.messages << "POST operation used, will merge query parameters with defaults"
    end
    
    @json.result_data = []
        
    c.design_docs[params[:ddoc]].send(params[:view].to_sym, query_params).each do |r|
      row_values = Map.new({
        index_key: r.key,
        row_value: r.value        
      })
      if query_params[:include_docs]
        row_values.doc = r.doc #if query_params.has_key? "include_docs") && query_params["include_docs"]
      end
      
      unless query_params[:reduce]
        row_values.meta_id = r.id
      end
      
      @json.result_data << row_values
    end

    @json.code = 200
    @json.success = true
    @json.messages << "View Query completed"
    
    render json: @json    
  end
  
  
  #workaround since Hash has a default method
  def get_connection(b)
    if b == "default"
      $cb.connections.default
    else
      $cb.connections[b]
    end
  end
  
  def validate_bucket_connection(p)

    b = p[:bucket]
    b ||= "default"
    
    unless $cb.buckets.include? b
      json = {
        code: 404,
        success: false,
        error_message: "Bucket [#{b}] not found"
      }
      render json: json and return nil, nil
    end
    json = Map.new({
      code: 404,
      success: false,
      operation: { command: caller_locations(1,1)[0].label, method: request.method.upcase },
      messages: []     
    })
    
    if p[:bucket]
      json.messages << "Bucket [#{b}] specified and found"
    else
      json.messages << "Bucket not specified, [default] being used"
    end
    
    p.each_pair do |k, v|
      json.operation[k] = v unless ["controller", "action", "serve"].include? k.to_s
    end
    
    return get_connection(b), json
  end

  def default_format_json
    if(request.headers["HTTP_ACCEPT"].nil? &&
       params[:format].nil?)
      request.format = "json"
    end
  end
  
  def guess_data_type(doc)
    case doc
    when Fixnum
      "Integer"
    when Hash
      "json"
    else
      doc.class.to_s.capitalize
    end
  end
  
end
