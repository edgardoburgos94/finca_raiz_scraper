require 'nokogiri'
require 'httparty'
require 'byebug'
require 'action_view'
require 'launchy'

class FincaRaizScraper
  attr_accessor :base_url, :path, :accepted_price_per_square_meter, :max_price

	def initialize(options = default_search_params)
		@base_url = options.fetch(:base_url)
		@path = options.fetch(:path)
		@accepted_price_per_square_meter = options.fetch(:accepted_price_per_square_meter)
		@max_price = options.fetch(:max_price)
	end

	def run
		page_number = 1
		last_page = page_number
		nice_apartments = []
		while page_number <= last_page
			parsed_page = parsed_data_from_path(path(page_number))
			apartments_adverts = parsed_page.css('ul.advert')
			nice_apartments = select_best_apartments(apartments_adverts, nice_apartments)
			last_page = parsed_page.css('a.link-pag')[-2].text.strip.to_i
			page_number = page_number + 1

			print_status_of_the_search(last_page, page_number, nice_apartments)
		end
	
		print_results(nice_apartments)
	end

	def parsed_data_from_path(path)
		puts "Fetching data from #{@base_url + path}"
		unparsed_page = HTTParty.get(@base_url + path)
		raise 'An error has occured' if unparsed_page.body.nil?
		Nokogiri::HTML(unparsed_page.body)
	end

	def select_best_apartments(apartments_adverts, nice_apartments)
		apartments_adverts.each do |apartments_advert|
			apartment_path = apartments_advert.css('li.surface').at('li')['onclick'].scan(/'([^']*)'/).flatten.first
			surface = apartments_advert.css('li.surface').text.strip.split('m2').first.to_f
			price = apartments_advert.css('li.price').text.strip.split("\r\n").first.sub('$', '').gsub('.', '').to_f
			price_per_square_meter= price/surface
			if is_an_affordable_appartment?(price, price_per_square_meter)
				admon = admon_value(apartment_path, price)
				price = price + admon
				price_per_square_meter= price/surface
				if is_an_affordable_appartment?(price, price_per_square_meter)
					nice_apartment = {
						price: price,
						surface: surface,
						apartment_path: @base_url + apartment_path,
						price_per_square_meter: price_per_square_meter
					}
					Launchy.open(nice_apartment[:apartment_path])
					nice_apartments << nice_apartment
				end
			end
		end
		nice_apartments
	end

	def admon_value(apartment_path, price)
		appartment_advert_page_parsed = parsed_data_from_path(apartment_path)
		boxcube = appartment_advert_page_parsed.css('ul.boxcube').text
		admon_location = nil
		splited_boxcube = boxcube.split("\r\n")
		splited_boxcube.each_with_index do |val, index|
			admon_location = index if /Admón/.match(val)
		end
		return 0 if admon_location.nil? 
		
		admon_value = splited_boxcube[admon_location + 1].strip
		return 0 if /Incluida/.match(admon_value)
	
		admon_value.gsub("$", "").gsub(",", "").to_f
	end

	def is_an_affordable_appartment?(price, price_per_square_meter)
		price <= @max_price && price_per_square_meter <= @accepted_price_per_square_meter
	end

	def print_results(nice_apartments)
		puts '--------LISTA DE APARTAMENTOS-----------'
		action_view = ActionView::Base.new
		nice_apartments.each do |apartment|
			puts "PRECIO: #{action_view.number_to_currency(apartment[:price])}"
			puts "AREA: #{apartment[:surface]}"
			puts "PRECIO/AREA: #{action_view.number_to_currency(apartment[:price_per_square_meter])}"
			puts "LINK: #{apartment[:apartment_path]}"
			puts '---------------------------'
		end
	end

	def print_status_of_the_search(last_page, page_number, nice_apartments)
		puts '-----------------------------'
		puts '-----------------------------'
		puts "      CURRENT PAGE #{page_number}"
		puts "      LAST PAGE #{last_page}"
		puts "      NICE APARTMENTS #{nice_apartments.count}"
		puts '-----------------------------'
		puts '-----------------------------'
  end
	
	def default_search_params()
		{
			base_url: 'https://www.fincaraiz.com.co',
			path: path(1),
			accepted_price_per_square_meter: 29_000,
			max_price: 1_200_000
		}
	end

	def path(page_number)
		# "/apartamento-apartaestudio/arriendo/bogota/?ad=30|#{page_number}||||2||8,22|||67|3630001|||2000000|||40||1,2||||||||1|||1||griddate%20desc||||-1|5|"
		"/apartamento-apartaestudio/arriendo/bogota/?ad=30|#{page_number}||||2||8,22|||67|3630001|||2000000|||40||1,2||||||129||1|||1||price%20asc||||-1|4|"
	end
end

FincaRaizScraper.new.run
