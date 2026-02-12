#Quiero automatizar un script para hacer lo siguiente

#1. primero va moverse a la carpeta
cd ~/Proyectos/Picade-app

#2. destruir y levantar nuevamente los contenedores
docker compose down 

docker compose build --no-cache

docker compose run --rm app composer install

docker compose up -d

#3. reinstalara las dependencias 
docker exec -it PICADE_APP composer install

docker exec -it PICADE_APP npm install

#4. dara permisos para editar lo creado
chown -R jesus:jesus .

#5. cargara los archivos csv a la memoria.
docker exec -it PICADE_DB ls /var/lib/mysql-files/

#6. copiara todos los archivos al contenedor desde la libreria.
docker cp ./docker/mariadb/csv/. PICADE_DB:/var/lib/mysql-files/

#7. daremos permios por si se perdieron
docker exec -u root PICADE_DB chmod -R 777 /var/lib/mysql-files/

#8. limpiaremos el cache
docker exec -it PICADE_APP php artisan config:clear

docker exec -it PICADE_APP php artisan cache:clear

docker exec -it PICADE_APP php artisan route:clear

#9. Crearemos la base de datos
sudo docker exec -it PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN -e "DROP DATABASE IF EXISTS PICADE; CREATE DATABASE PICADE;"

#10. generaremos una nueva clave 
docker exec -it PICADE_APP php artisan key:generate

#11. ejecutaremos las migraciones 
docker exec -it PICADE_APP php artisan migrate

#12. movernos a la carpeta init
cd ~/Proyectos/Picade-app/docker/mariadb/init/

#13. Crear las tablas personalizadas, cargar los datos y y crear vistas y procedimientos en orden.
docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "0_PICADE-FINAL-09-02-26.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "01_CargarMasivaCSV.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "1. PROCEDIMIENTOS-GESTION_GEOGRAFICA.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "2. PROCEDIMIENTOS-ORGANIZACION_INTERNA.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "3. PROCEDIMIENTOS_CENTROS_DE_TRABAJO.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "4. PROCEDIMIENTOS_DEPARTAMENTOS.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "5. PROCEDIMIENTOS-CASES.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "6. PROCEDIMIENTOS-REGIMEN_TRABAJO.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "7. PROCEDIMIENTOS-PUESTOS_TRABAJO.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "8. PROCEDIMIENTOS-REGION_OPERATIVA.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "9. PROCEDIMIENTOS-ROL_USER.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "10. PROCEDIMIENTOS-USUARIO_INFOPERSONAL.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "11_PROCEDIMIENTOS_TIPOS_INSTRUCCIONES.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "12_PROCEDIMIENTOS_TEMAS_CAPACITACION.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "13_PROCEDIMIENTOS_ESTATUS_CAPACITACION.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "14_PROCEDIMIENTOS_MODALIDAD_CAPACITACION.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "15_PROCEDIMIENTOS_ESTATUS_PARTICIPANTE.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "16. PROCEDIMIENTOS_CAPACITACIONES.sql"

docker exec -i PICADE_DB mariadb -u root -pROOT_PICADE_USER_ADMIN PICADE < "17. PROCEDIMIENTOS_PARTICIPANTES_DE_CAPACITACIONES.sql"


#14. generar link de acceso para los datos
docker exec -it PICADE_APP php artisan storage:link
