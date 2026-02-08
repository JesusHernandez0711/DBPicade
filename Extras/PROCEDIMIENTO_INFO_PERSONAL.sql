
SELECT
	`Usuarios`.`Id_Usuario` AS `Id_Usuario`, 
	`Usuarios`.`Ficha` AS `Ficha_User`, 
	`Usuarios`.`Email` AS `Email_User`, 
	`Info_User`.`Nombre` AS `Nombre_Usuario`, 
	`Info_User`.`Apellido_Paterno`, 
	`Info_User`.`Apellido_Materno`, 
	`Info_User`.`Fecha_Nacimiento`, 
	`Info_User`.`Fecha_Ingreso`, 
	`Regimen`.`Nombre` AS `Regimen`, 
	`Puesto`.`Nombre` AS `Puesto`, 
	`Vista_CT`.`Codigo_CT`, 
	`Vista_CT`.`Nombre_CT`, 
	`Vista_Dep`.`Codigo_Departamento`, 
	`Vista_Dep`.`Nombre_Departamento`, 
	`Region`.`Nombre` AS `Region`, 
	`Vista_Org`.`Clave_Gerencia`, 
	`Vista_Org`.`Nombre_Gerencia`, 
	`Vista_Org`.`Clave_Subdireccion`, 
	`Vista_Org`.`Nombre_Subdireccion`, 
	`Vista_Org`.`Clave_Direccion`, 
	`Vista_Org`.`Nombre_Direccion`, 
	`Info_User`.`Nivel` AS `Nivel_User`, 
	`Info_User`.`Clasificacion` AS `Clasificacion_User`, 
	`Roles`.`Nombre` AS `Rol_User`, 
	`Usuarios`.`Activo` AS `Estatus_User`
FROM
	`Usuarios`
	INNER JOIN
	`Info_Personal` AS `Info_User`
	ON 
		`Usuarios`.`Fk_Id_InfoPersonal` = `Info_User`.`Id_InfoPersonal`
	LEFT JOIN
	`Cat_Regimenes_Trabajo` AS `Regimen`
	ON 
		`Info_User`.`Fk_Id_CatRegimen` = `Regimen`.`Id_CatRegimen`
	LEFT JOIN
	`Cat_Puestos_Trabajo` AS `Puesto`
	ON 
		`Info_User`.`Fk_Id_CatPuesto` = `Puesto`.`Id_CatPuesto`
	LEFT JOIN
	`Vista_Centros_Trabajo` AS `Vista_CT`
	ON 
		`Info_User`.`Fk_Id_CatCT` = `Vista_CT`.`Id_CentroTrabajo`
	LEFT JOIN
	`Vista_Departamentos` AS `Vista_Dep`
	ON 
		`Info_User`.`Fk_Id_CatDep` = `Vista_Dep`.`Id_Departamento`
	LEFT JOIN
	`Cat_Regiones_Trabajo` AS `Region`
	ON 
		`Info_User`.`Fk_Id_CatRegion` = `Region`.`Id_CatRegion`
	LEFT JOIN
	`Vista_Organizacion` AS `Vista_Org`
	ON 
		`Info_User`.`Fk_Id_CatGeren` = `Vista_Org`.`Id_Gerencia`
	INNER JOIN
	`Cat_Roles` AS `Roles`
	ON 
		`Usuarios`.`Fk_Rol` = `Roles`.`Id_Rol`;
        
SELECT
	`Usuarios`.`Id_Usuario`, 
	`Usuarios`.`Ficha`,
	`Usuarios`.`Email`, 
	`Info_User`.`Nombre` AS `Nombre_Usuario`, 
	`Info_User`.`Apellido_Paterno`, 
	`Info_User`.`Apellido_Materno`, 
	`Roles`.`Nombre` AS `Rol_User`, 
	`Usuarios`.`Activo` AS `Estatus_User`
FROM
	`Usuarios`
	INNER JOIN
	`Info_Personal` AS `Info_User`
	ON 
		`Usuarios`.`Fk_Id_InfoPersonal` = `Info_User`.`Id_InfoPersonal`
	INNER JOIN
	`Cat_Roles` AS `Roles`
	ON 
		`Usuarios`.`Fk_Rol` = `Roles`.`Id_Rol`;

