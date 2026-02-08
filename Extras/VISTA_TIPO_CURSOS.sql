use Picade;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS                                */
/* ------------------------------------------------------------------------------------------------------ */

SELECT
	`Cat_Cap`.`Id_CatCap` AS `Id_Cap`, 
	`Cat_Cap`.`Codigo` AS `Codigo_Cap`, 
	`Cat_Cap`.`Nombre` AS `Nombre_Cap`, 
	-- `Cat_Cap`.`Descripcion` AS `Descripcion_Cap`, 
	`Cat_Cap`.`Duracion_Horas` AS `Duracion_Horas_Cap`,
	-- `Cat_TipoCap`.`Id_CatTipoCap` AS `Id_Tipo_CatCap`,
	`Cat_TipoCap`.`Nombre` AS `Nombre_TipoCap`, 
	-- `Cat_TipoCap`.`Descripcion` AS `Descripcion_TipoCap`, 
	`Cat_Cap`.`Activo` AS `Estatus_Cap`
FROM
	`Cat_Capacitacion` AS `Cat_Cap`
	LEFT JOIN
	`Cat_Tipo_Capacitacion` AS `Cat_TipoCap`
	ON 
		`Cat_Cap`.`Fk_Id_CatTipoCap` = `Cat_TipoCap`.`Id_CatTipoCap`;
        
USE Picade;