docker compose down 

docker compose build --no-cache

docker compose run --rm app composer install

docker compose up -d

sudo docker exec -it PICADE_APP php artisan serve --host=0.0.0.0 --port=8000

sudo docker exec -it PICADE_APP npm run dev -- --host

sudo chown -R jesus:jesus .

id

docker exec -it PICADE_APP php artisan make:model Usuario

docker exec -it PICADE_APP php artisan config:clear

docker exec -it PICADE_APP php artisan make:controller Auth/LoginController

docker exec -it PICADE_APP php artisan make:controller Auth/RegisterController

docker exec -it PICADE_APP php artisan make:controller UsuarioController --resource

docker exec -it PICADE_APP php artisan make:controller CatalogoController

docker exec -it PICADE_APP php artisan config:clear

docker exec -it PICADE_APP php artisan cache:clear

docker exec -it PICADE_APP php artisan route:clear

chmod +x setup.sh

./setup.sh