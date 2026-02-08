SELECT
	Vista_Capacitaciones.Numero_Capacitacion, 
	Vista_Capacitaciones.Clave_Gerencia, 
	Vista_Capacitaciones.Nombre_Tema, 
	Vista_Capacitaciones.Ficha_Usuario, 
	Vista_Capacitaciones.Apellido_Paterno, 
	Vista_Capacitaciones.Apellido_Materno, 
	Vista_Capacitaciones.Nombre, 
	Vista_Capacitaciones.Fecha_Inicio, 
	Vista_Capacitaciones.Fecha_Fin, 
	Vista_Capacitaciones.Nombre_Sedes, 
	Vista_Capacitaciones.Nombre_Modalidad, 
	Vista_Capacitaciones.Nombre_Estatus, 
	vista_usuarios.Ficha_Usuario, 
	vista_usuarios.Nombre, 
	vista_usuarios.Apellido_Paterno, 
	vista_usuarios.Apellido_Materno, 
	vista_estatus_participante.Nombre_Estatus, 
	vista_estatus_participante.Descripcion_Estatus, 
	capacitaciones_participantes.PorcentajeAsistencia, 
	capacitaciones_participantes.Calificacion, 
	Vista_Capacitaciones.Activo
FROM
	capacitaciones_participantes
	INNER JOIN
	Vista_Capacitaciones
	ON 
		capacitaciones_participantes.Fk_Id_DatosCap = Vista_Capacitaciones.Id_DatosCap
	INNER JOIN
	vista_usuarios
	ON 
		capacitaciones_participantes.Fk_Id_Usuario = vista_usuarios.Id_Usuario
	INNER JOIN
	vista_estatus_participante
	ON 
		capacitaciones_participantes.Fk_Id_CatEstPart = vista_estatus_participante.Id_Estatus_Participante