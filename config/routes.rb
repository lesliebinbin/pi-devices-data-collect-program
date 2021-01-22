Rails.application.routes.draw do
  post '/data', to: 'data#accept'
  post '/trackerjacker', to: 'data#tracker'
  post '/dmesg', to: 'data#dmesg'
  get '/update_pi_info', to: 'data#update_pi_info'
  post '/ubertooth', to: 'data#ubertooth'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end
