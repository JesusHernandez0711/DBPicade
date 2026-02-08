SELECT '--- 🔍 AUDITORÍA C07: Validación de Vistas por Rol ---' AS STEP;

-- =================================================================================
-- 1. VISTA DEL COORDINADOR (Dueño del Curso)
-- =================================================================================
-- ¿Qué busca? Confirmar que el curso existe, pero está marcado como "CANCELADO" y "ARCHIVADO".
SELECT 
    'COORDINADOR' AS Rol_Vista,
    C.Numero_Capacitacion AS Folio,
    C.Activo AS Es_Visible_General, -- Si es 0, no sale en listas normales
    DC.Version,
    E.Descripcion AS Estatus_Actual, -- Debe decir "CANCELADO" (ID 8)
    DC.Observaciones AS Justificacion, -- Debe decir "Cancelado"
    DATE_FORMAT(DC.updated_at, '%Y-%m-%d %H:%i') AS Fecha_Cancelacion
FROM DatosCapacitaciones DC
INNER JOIN Capacitaciones C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
INNER JOIN Cat_Estatus_Capacitacion E ON DC.Fk_Id_CatEstCap = E.Id_CatEstCap
WHERE C.Numero_Capacitacion = 'QA-DIAMOND-C07'
ORDER BY DC.Version DESC LIMIT 1;


-- =================================================================================
-- 2. VISTA DEL INSTRUCTOR (Asignado)
-- =================================================================================
-- ¿Qué busca? Saber si todavía tiene este curso en su carga de trabajo o si aparece tachado.
SELECT 
    'INSTRUCTOR' AS Rol_Vista,
    CONCAT(IP.Nombre, ' ', IP.Apellido_Paterno) AS Instructor_Asignado,
    C.Numero_Capacitacion,
    E.Descripcion AS Estatus_Curso
FROM DatosCapacitaciones DC
INNER JOIN Capacitaciones C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
INNER JOIN Usuarios U ON DC.Fk_Id_Instructor = U.Id_Usuario
INNER JOIN Info_Personal IP ON U.Fk_Id_InfoPersonal = IP.Id_InfoPersonal
INNER JOIN Cat_Estatus_Capacitacion E ON DC.Fk_Id_CatEstCap = E.Id_CatEstCap
WHERE C.Numero_Capacitacion = 'QA-DIAMOND-C07'
AND U.Id_Usuario = @U_Inst1 -- Filtramos como si fueramos el instructor logueado
ORDER BY DC.Version DESC LIMIT 1;


-- =================================================================================
-- 3. VISTA DEL PARTICIPANTE (Alumno P01)
-- =================================================================================
-- ¿Qué busca? Ver si su inscripción sigue viva. 
-- IMPORTANTE: Aunque el curso se cancele, el registro del alumno NO SE BORRA, 
-- pero hereda el estatus del curso visualmente.
SELECT 
    'PARTICIPANTE' AS Rol_Vista,
    CONCAT(IP.Nombre, ' ', IP.Apellido_Paterno) AS Alumno,
    C.Numero_Capacitacion AS Curso,
    
    -- Estatus del Curso (Lo que define si hay clase o no)
    E_Curso.Descripcion AS Estatus_Curso, 
    
    -- Estatus del Alumno (Sigue inscrito, pero en un barco hundido)
    E_Part.Descripcion AS Estatus_Alumno_Interno,
    
    CP.Justificacion AS Nota_Expediente
FROM Capacitaciones_Participantes CP
INNER JOIN DatosCapacitaciones DC ON CP.Fk_Id_DatosCap = DC.Id_DatosCap
INNER JOIN Capacitaciones C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
INNER JOIN Usuarios U ON CP.Fk_Id_Usuario = U.Id_Usuario
INNER JOIN Info_Personal IP ON U.Fk_Id_InfoPersonal = IP.Id_InfoPersonal
INNER JOIN Cat_Estatus_Capacitacion E_Curso ON DC.Fk_Id_CatEstCap = E_Curso.Id_CatEstCap
INNER JOIN Cat_Estatus_Participante E_Part ON CP.Fk_Id_CatEstPart = E_Part.Id_CatEstPart
WHERE C.Numero_Capacitacion = 'QA-DIAMOND-C07'
AND U.Id_Usuario = @U_P01; -- Filtramos como si fueramos el alumno P01