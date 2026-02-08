SELECT
	Cap.Id_Capacitacion,
	Cap.Numero_Capacitacion, 
	Org.Clave_Gerencia, 
	Tem.Codigo_Tema, 
	Tem.Nombre_Tema, 
	Tem.Nombre_Tipo_Instruccion, 
	Tem.Duracion_Horas, 
	Cap.Asistentes_Programados, 
	Us.Ficha_Usuario, 
	Us.Apellido_Paterno, 
	Us.Apellido_Materno, 
	Us.Nombre, 
	DatCap.Fecha_Inicio, 
	DatCap.Fecha_Fin, 
	Sede.Codigo_Sedes, 
	Sede.Nombre_Sedes, 
	`Moda`.Codigo_Modalidad, 
	`Moda`.Nombre_Modalidad, 
	EstCap.Codigo_Estatus, 
	EstCap.Nombre_Estatus, 
	DatCap.AsistentesReales, 
	DatCap.Observaciones, 
	DatCap.Activo 
FROM
	capacitaciones AS Cap
	INNER JOIN
	datoscapacitaciones AS DatCap
	ON 
		Cap.Id_Capacitacion = DatCap.Fk_Id_Capacitacion
	INNER JOIN
	vista_usuarios AS Us
	ON 
		DatCap.Fk_Id_Instructor = Us.Id_Usuario
	/*INNER JOIN
	vista_roles AS Role
	ON 
		Us.Rol_Usuario = Role.Id_Rol*/
	INNER JOIN
	vista_organizacion AS Org
	ON 
		Cap.Fk_Id_CatGeren = Org.Id_Gerencia
	INNER JOIN
	vista_temas_capacitacion AS Tem
	ON 
		Cap.Fk_Id_Cat_TemasCap = Tem.Id_Tema
	/*INNER JOIN
	vista_tipos_instruccion AS Tipo_T
	ON 
		Tem.Nombre_Tipo_Instruccion = Tipo_T.Id_Tipo_Instruccion*/
	INNER JOIN
	vista_sedes AS Sede
	ON 
		DatCap.Fk_Id_CatCases_Sedes = Sede.Id_Sedes
	INNER JOIN
	vista_modalidad_capacitacion AS `Moda`
	ON 
		DatCap.Fk_Id_CatModalCap = `Moda`.Id_Modalidad
	INNER JOIN
	vista_estatus_capacitacion AS EstCap
	ON 
		DatCap.Fk_Id_CatEstCap = EstCap.Id_Estatus_Capacitacion