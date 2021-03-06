class BargainFinderMax
  
  # == Includes ===============================================================
  include ActiveModel::Model
  
  # == Constants ==============================================================
  BARGAIN_FINDER_MAX_RQ_WSDL          = "http://files.developer.sabre.com/wsdl/sabreXML1.0.00/shopping/BargainFinderMaxRQ_v1-9-2.wsdl"
  HEADER_ACTION_BARGAIN_FINDER_MAX_RQ = "BargainFinderMaxRQ"

  TRIP_TYPE_ONE_WAY                   = "OneWay"
  TRIP_TYPE_RETURN                    = "Return"
  TRIP_TYPE_CIRCLE                    = "Circle"
  
  # == Class Methods ==========================================================
  def self.extract_air_itinerary(air_itinerary)
    extracted_origin_destination_options = nil

    raise "Passed 'air_itinerary' is not a Hash."   unless air_itinerary.class == Hash

    raise "Passed 'air_itinerary' was nil."   if air_itinerary.nil?
    
    raise "Passed 'air_itinerary' was empty." if air_itinerary.empty?

    origin_destination_option = (air_itinerary[:origin_destination_options])[:origin_destination_option]
    
    if    origin_destination_option.class == Array
      extracted_origin_destination_options =   origin_destination_option
    elsif origin_destination_option.class == Hash
      extracted_origin_destination_options = [ origin_destination_option ]
    else
      raise "Expecting 'origin_destination_option' to have a return type of either an Array or Hash. The actual return type was '#{origin_destination_option.class}'."
    end    
    
    return extracted_origin_destination_options
  end
  
  def self.build_origin_and_destination(departure_date_time, origin_location, destination_location)
    return { departure_date_time: departure_date_time, origin_location: origin_location, destination_location: destination_location }
  end  
  
  def self.build_passenger_type_and_quantity(passenger_type, quantity)
    return { passenger_type: passenger_type, quantity: quantity }
  end
  
  # == Instance methods =======================================================
  def initialize
    @savon_client = nil
    @message_body = {}
  end  
  
  def establish_connection(session)
    raise "Passed 'session' parameter was nil. Said parameter must not be nil." if session.nil?
    
    @savon_client = Savon.client(
      wsdl:                    BARGAIN_FINDER_MAX_RQ_WSDL, 
      namespaces:              namespaces,
      soap_header:             session.build_header(HEADER_ACTION_BARGAIN_FINDER_MAX_RQ, session.binary_security_token),
      log:                     true, 
      log_level:               :debug, 
      pretty_print_xml:        true,
      convert_request_keys_to: :none,
      namespace_identifier:    :ns
    )
    
    @savon_client = session.set_endpoint_environment(@savon_client)

    return @savon_client
  end
  
  def operation_attributes
    attributes = {
      "Target"          => "Production",
      "Version"         => "1.9.2",
      "ResponseType"    => "OTA",
      "ResponseVersion" => "1.9.2",
    }
    
    return attributes
  end  
  
  def namespaces
    namespaces = {
      "xmlns:env" => "http://schemas.xmlsoap.org/soap/envelope/", 
      "xmlns:ns"  => "http://www.opentravel.org/OTA/2003/05",
      "xmlns:mes" => "http://www.ebxml.org/namespaces/messageHeader", 
      "xmlns:sec" => "http://schemas.xmlsoap.org/ws/2002/12/secext"
    }
    
    return namespaces
  end  
  
  def build_pos_section
    section = {
      "ns:Source" => {
        :@PseudoCityCode => "6A3H",
        
        "ns:RequestorID" => {
          :@Type => "1",
          :@ID   => "1",

          "ns:CompanyName" => {
            :@Code => "TN",  
          },
        },
      },
    }
    
    return section
  end
  
  def build_origin_destination_information_section(origins_and_destinations)
    raise "'origins_and_destinations' parameters should not be empty." if origins_and_destinations.empty?
    
    origin_destination_list = []
    
    count = 0
    origins_and_destinations.each do |entry|
      count += 1
      origin_destination_list << {
        :@RPH => count,
        "ns:DepartureDateTime"   => { :content!      => entry[:departure_date_time ], },
        "ns:OriginLocation"      => { :@LocationCode => entry[:origin_location     ], },
        "ns:DestinationLocation" => { :@LocationCode => entry[:destination_location], },
      }
    end
    
    return origin_destination_list
  end  
  
  def build_travel_preferences_section(trip_type)
    section = {
      "ns:TPA_Extensions" => {
        "ns:TripType" => {
          :@Value => trip_type,
        },
      },
    }
    
    return section
  end
  
  def build_passenger_type_quantity_section(passenger_types_and_quantities)
    raise "'passenger_types_and_quantities' parameters should not be empty." if passenger_types_and_quantities.empty?
    
    passenger_type_quantity_list = []
    
    seats_requested = 0
    passenger_types_and_quantities.each do |entry|
      passenger_type_quantity_list << {
        :@Code     => entry[:passenger_type],
        :@Quantity => entry[:quantity      ],
      }
      seats_requested += (entry[:quantity]).to_i
    end
    
    return seats_requested, passenger_type_quantity_list
  end  
  
  def build_message_body(origins_and_destinations, trip_type, passenger_types_and_quantities, request_type)
  
    pos_section                                   = build_pos_section
    origin_destination_information_section        = build_origin_destination_information_section(origins_and_destinations)
    travel_preferences_section                    = build_travel_preferences_section(TRIP_TYPE_ONE_WAY)
    seats_requested, passenger_type_quantity_list = build_passenger_type_quantity_section(passenger_types_and_quantities)

    message_body = {
      "ns:POS"                          => pos_section,
      "ns:OriginDestinationInformation" => origin_destination_information_section, 
      "ns:TravelPreferences"            => travel_preferences_section,
      "ns:TravelerInfoSummary" => {
        "ns:SeatsRequested"    => seats_requested,
        "ns:AirTravelerAvail"  => {
          "ns:PassengerTypeQuantity" => passenger_type_quantity_list,
        },
      },
      "ns:TPA_Extensions" => {
        "ns:IntelliSellTransaction" => {
          "ns:RequestType" => {
            :@Name => request_type,
          },
        },
      },
    } 
    
    return message_body 
  end  

  def extract_departure_date_time(origin_destionation_option)
    return origin_destionation_option[:flight_segment][:@departure_date_time]
  end
  
  def extract_flight_number(origin_destionation_option)
    return origin_destionation_option[:flight_segment][:@flight_number]
  end
  
  def extract_res_book_desig_code(origin_destionation_option) 
    return origin_destionation_option[:flight_segment][:@res_book_desig_code]  
  end
  
  def extract_location_code_destination_location(origin_destionation_option)
    return origin_destionation_option[:flight_segment][:arrival_airport][:@location_code]
  end
  
  def extract_code_marketing_airline(origin_destionation_option) 
    return origin_destionation_option[:flight_segment][:marketing_airline][:@code]
  end
  
  def extract_location_code_origin_location(origin_destionation_option)
    return origin_destionation_option[:flight_segment][:departure_airport][:@location_code]
  end
  
#####
  def self.extract_departure_date_time_for_api(origin_destionation_option)
    return origin_destionation_option["flight_segment"]["@departure_date_time"]
  end

  def self.extract_flight_number_for_api(origin_destionation_option)
    return origin_destionation_option["flight_segment"]["@flight_number"]
  end

  def self.extract_res_book_desig_code_for_api(origin_destionation_option) 
    return origin_destionation_option["flight_segment"]["@res_book_desig_code"]  
  end

  def self.extract_location_code_destination_location_for_api(origin_destionation_option)
    return origin_destionation_option["flight_segment"]["arrival_airport"]["@location_code"]
  end

  def self.extract_code_marketing_airline_for_api(origin_destionation_option) 
    return origin_destionation_option["flight_segment"]["marketing_airline"]["@code"]
  end

  def self.extract_location_code_origin_location_for_api(origin_destionation_option)
    return origin_destionation_option["flight_segment"]["departure_airport"]["@location_code"]
  end  
  
  def self.extract_air_itinerary_for_api(air_itinerary)
    extracted_origin_destination_options = nil
    
    raise "Passed 'air_itinerary' is not a Hash."   unless air_itinerary.class == Hash

    raise "Passed 'air_itinerary' was nil."   if air_itinerary.nil?
    
    raise "Passed 'air_itinerary' was empty." if air_itinerary.empty?
    
    origin_destination_option = (air_itinerary["origin_destination_options"])["origin_destination_option"]

    if    origin_destination_option.class == Array
      extracted_origin_destination_options =   origin_destination_option
    elsif origin_destination_option.class == Hash
      extracted_origin_destination_options = [ origin_destination_option ]
    else
      raise "Expecting 'origin_destination_option' to have a return type of either an Array or Hash. The actual return type was '#{origin_destination_option.class}'."
    end    

    return extracted_origin_destination_options
  end
#####
  
  def air_availability_one_way(origins_and_destinations, passenger_types_and_quantities, request_type="50ITINS")

    raise "No established 'savon_client' instance." if @savon_client.nil?

    begin
      @message_body = build_message_body(origins_and_destinations, TRIP_TYPE_ONE_WAY, passenger_types_and_quantities, request_type)  
      call_response = @savon_client.call(:bargain_finder_max_rq,  soap_action: "ns:OTA_AirLowFareSearchRQ", attributes: operation_attributes, message: @message_body)
    rescue Savon::Error => error
      puts "@DEBUG #{__LINE__}    #{ap error.to_hash[:fault]}"
      
      return { status: :failed,  error: error.to_hash[:fault] }
    else
      priced_itineraries = ((call_response.body[:ota_air_low_fare_search_rs])[:priced_itineraries])[:priced_itinerary]
      
      return { status: :success, data: { priced_itineraries: priced_itineraries } }
    end      
  end

  def air_availability_return(origins_and_destinations, passenger_types_and_quantities, request_type="50ITINS")
    
    raise "No established 'savon_client' instance." if @savon_client.nil?

    begin
      @message_body = build_message_body(origins_and_destinations, TRIP_TYPE_RETURN, passenger_types_and_quantities, request_type)  
      call_response = @savon_client.call(:bargain_finder_max_rq,  soap_action: "ns:OTA_AirLowFareSearchRQ", attributes: operation_attributes, message: @message_body)
    rescue Savon::Error => error
      puts "@DEBUG #{__LINE__}    #{ap error.to_hash[:fault]}"
      
      return { status: :failed,  error: error.to_hash[:fault] }
    else
      priced_itineraries = ((call_response.body[:ota_air_low_fare_search_rs])[:priced_itineraries])[:priced_itinerary]
      
      return { status: :success, data: { priced_itineraries: priced_itineraries } }
    end
  end

  def air_availability_circle(origins_and_destinations, passenger_types_and_quantities, request_type="50ITINS")

    raise "No established 'savon_client' instance." if @savon_client.nil?

    begin
      @message_body = build_message_body(origins_and_destinations, TRIP_TYPE_CIRCLE, passenger_types_and_quantities, request_type)  
      call_response = @savon_client.call(:bargain_finder_max_rq,  soap_action: "ns:OTA_AirLowFareSearchRQ", attributes: operation_attributes, message: @message_body)
    rescue Savon::Error => error
      puts "@DEBUG #{__LINE__}    #{ap error.to_hash[:fault]}"
      
      return { status: :failed,  error: error.to_hash[:fault] }
    else
      priced_itineraries = ((call_response.body[:ota_air_low_fare_search_rs])[:priced_itineraries])[:priced_itinerary]
      
      return { status: :success, data: { priced_itineraries: priced_itineraries } }
    end
  end
  
end
