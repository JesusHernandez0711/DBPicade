USE PICADE;

SELECT * FROM `PICADE`.PAIS;

SELECT * FROM  `PICADE`.ESTADO;

SELECT * FROM  `PICADE`.MUNICIPIO;

SELECT * FROM `PICADE`.CAT_DIRECCIONES;

SELECT * FROM `PICADE`.CAT_SUBDIRECCIONES;

SELECT * FROM `PICADE`.CAT_GERENCIAS_ACTIVOS;

SELECT * FROM `PICADE`.CAT_REGIONES_TRABAJO;

SELECT * FROM `PICADE`.CAT_REGIMENES_TRABAJO;

SELECT * FROM `PICADE`.CAT_PUESTOS_TRABAJO;

SELECT * FROM `PICADE`.CAT_CASES_SEDES;

SELECT * FROM `PICADE`.cat_estatus_participante;

SELECT * FROM `PICADE`.CAT_TEMAS_CAPACITACION;

 SELECT  * FROM `PICADE`.CAT_ESTATUS_CAPACITACION;

SELECT * FROM `PICADE`.CAPACITACIONES_PARTICIPANTES;

SELECT * FROM CAT_MODALIDAD_CAPACITACION;

SELECT * FROM `PICADE`.vista_estatus_capacitacion;

SELECT * FROM `PICADE`.CAT_TEMAS_CAPACITACION;

SELECT * FROM `PICADE`.CAT_TIPOS_INSTRUCCION_CAP;

SELECT * FROM `PICADE`.Vista_Roles;

SELECT * FROM `Picade`.`Vista_Usuarios`;

CALL `PICADE`.SP_ConsultarPerfilPropio (322);

SELECT * FROM `PICADE`.CAPACITACIONES;

SELECT * FROM `PICADE`.DATOSCAPACITACIONES;

SELECT * FROM `PICADE`.CAPACITACIONES_PARTICIPANTES;

SELECT * FROM `PICADE`.`Vista_Capacitaciones`;

SET @FechaActual = CURDATE();

CALL SP_ObtenerMatrizPICADE(
    NULL,                            -- Filtramos sin ninguna gerencia de prueba
    @FechaActual,                           -- Fecha Inicio del rango visual
    DATE_ADD(@FechaActual, INTERVAL 360 DAY) -- Fecha Fin (para cubrir todos los cursos creados)
); 

SELECT * FROM `PICADE`.vista_gestion_de_participantes;

CAll SP_ConsultarCapacitacionEspecifica(26);

CAll SP_ConsultarCapacitacionEspecifica(25);

CAll SP_ConsultarCapacitacionEspecifica(24);

-- 1. Obtén el ID de la versión actual del curso C01
SET @Id_Version_Actual = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));

-- 2. Pregúntale a la base de datos cuántos alumnos tiene ESA versión específica
SELECT COUNT(*) AS Alumnos_Reales_En_Esta_Version 
FROM Capacitaciones_Participantes 
WHERE Fk_Id_DatosCap = @Id_Version_Actual;