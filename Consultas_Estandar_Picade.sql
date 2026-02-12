USE `PICADE`;

SELECT * FROM `PICADE`.`Pais`;

SELECT * FROM  `PICADE`.`Estado`;

SELECT * FROM  `PICADE`.`Municipio`;

SELECT * FROM `PICADE`.`Cat_Direcciones`;

SELECT * FROM `PICADE`.`Cat_Subdirecciones`;

SELECT * FROM `PICADE`.`Cat_Gerencias_Activos`;

SELECT * FROM `PICADE`.`Cat_Regiones_Trabajo`;

SELECT * FROM `PICADE`.`Cat_Regimenes_Trabajo`;

SELECT * FROM `PICADE`.`Cat_Puestos_Trabajo`;

SELECT * FROM `PICADE`.`Cat_Cases_Sedes`;

SELECT * FROM `PICADE`.`Cat_Estatus_Participante`;

SELECT * FROM `PICADE`.`Cat_Temas_Capacitacion`;

 SELECT  * FROM `PICADE`.`Cat_Estatus_Capacitacion`;

SELECT * FROM `PICADE`.`Capacitaciones_Participantes`;

SELECT * FROM `PICADE`.`Cat_Modalidad_Capacitacion`;

SELECT * FROM `PICADE`.`Vista_Estatus_Capacitacion`;

SELECT * FROM `PICADE`.`Cat_Temas_Capacitacion`;

SELECT * FROM `PICADE`.`Cat_Tipos_Instruccion_Cap`;

SELECT * FROM `PICADE`.`Vista_Roles`;

SELECT * FROM `PICADE`.`Vista_Usuarios`;

CALL `PICADE`.`SP_ConsultarPerfilPropio` (322);

SELECT * FROM `PICADE`.`Capacitaciones`;

SELECT * FROM `PICADE`.`DatosCapacitaciones`;

SELECT * FROM `PICADE`.`Capacitaciones_Participantes`;

SELECT * FROM `PICADE`.`Vista_Capacitaciones`;

SET @FechaActual = CURDATE();

CALL`SP_ObtenerMatrizPICADE`(
    NULL,                            -- Filtramos sin ninguna gerencia de prueba
    @FechaActual,                           -- Fecha Inicio del rango visual
    DATE_ADD(@FechaActual, INTERVAL 360 DAY) -- Fecha Fin (para cubrir todos los cursos creados)
); 

SELECT * FROM `PICADE`.`Vista_Gestion_de_Participantes`;

CAll `SP_ConsultarCapacitacionespecifica`(26);

CAll `SP_ConsultarCapacitacionespecifica`(25);

CAll `SP_ConsultarCapacitacionespecifica`(24);

-- 1. Obtén el ID de la versión actual del curso C01
SET @Id_Version_Actual = (
SELECT MAX(Id_DatosCap) 
FROM `DatosCapacitaciones` 
WHERE `Fk_Id_Capacitacion` = (
	SELECT `Id_Capacitacion` 
    FROM `Capacitaciones `
    WHERE `Numero_Capacitacion` = 'QA-DIAMOND-C01'
    )
);

-- 2. Pregúntale a la base de datos cuántos alumnos tiene ESA versión específica
SELECT COUNT(*) AS Alumnos_Reales_En_Esta_Version 
FROM `Capacitaciones_Participantes` 
WHERE `Fk_Id_DatosCap` = @Id_Version_Actual;

SELECT * FROM `PICADE`.`Usuarios` Where `Id_Usuario`=322;