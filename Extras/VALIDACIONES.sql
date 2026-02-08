/* =====================================================================================
   POST-CARGA PICADE — CHECKLIST DE INTEGRIDAD + CALIDAD DE DATOS
   - Pega y ejecuta por secciones (o todo junto si tu cliente soporta multi-statements).
   - Objetivo: detectar tablas vacías, huérfanos de FK, duplicados, strings vacíos/espacios.
===================================================================================== */

USE `PICADE`;

/* =====================================================================================
   1) SMOKE TEST: CONTEOS POR TABLA
   (Sirve para detectar tablas vacías o con conteos “raros” tras la carga masiva)
===================================================================================== */
SELECT
  table_name AS tabla,
  table_rows AS filas_estimadas
FROM information_schema.tables
WHERE table_schema = 'PICADE'
ORDER BY table_name;

/* =====================================================================================
   2) VALIDACIÓN DE LLAVES FORÁNEAS (HUÉRFANOS)
   (Cada query DEBE devolver 0 filas. Si devuelve algo: hay FK inválida/carga mala)
===================================================================================== */

-- 2.1 Estado -> Pais (Fk_Id_Pais debe existir en Pais.Id_Pais)
SELECT e.Id_Estado, e.Fk_Id_Pais
FROM Estado e
LEFT JOIN Pais p ON p.Id_Pais = e.Fk_Id_Pais
WHERE p.Id_Pais IS NULL;

-- 2.2 Municipio -> Estado (Fk_Id_Estado debe existir en Estado.Id_Estado)
SELECT m.Id_Municipio, m.Fk_Id_Estado
FROM Municipio m
LEFT JOIN Estado e ON e.Id_Estado = m.Fk_Id_Estado
WHERE e.Id_Estado IS NULL;

-- 2.3 Cat_Centros_Trabajo -> Municipio (solo valida cuando Fk_Id_Municipio_CatCT NO es NULL)
SELECT ct.Id_CatCT, ct.Fk_Id_Municipio_CatCT
FROM Cat_Centros_Trabajo ct
LEFT JOIN Municipio m ON m.Id_Municipio = ct.Fk_Id_Municipio_CatCT
WHERE ct.Fk_Id_Municipio_CatCT IS NOT NULL
  AND m.Id_Municipio IS NULL;

-- 2.4 Cat_Departamentos -> Municipio (solo valida cuando Fk_Id_Municipio_CatDep NO es NULL)
SELECT d.Id_CatDep, d.Fk_Id_Municipio_CatDep
FROM Cat_Departamentos d
LEFT JOIN Municipio m ON m.Id_Municipio = d.Fk_Id_Municipio_CatDep
WHERE d.Fk_Id_Municipio_CatDep IS NOT NULL
  AND m.Id_Municipio IS NULL;

-- 2.5 Cat_Subdirecciones -> Cat_Direcciones (Fk_Id_CatDirecc debe existir)
SELECT s.Id_CatSubDirec, s.Fk_Id_CatDirecc
FROM Cat_Subdirecciones s
LEFT JOIN Cat_Direcciones d ON d.Id_CatDirecc = s.Fk_Id_CatDirecc
WHERE d.Id_CatDirecc IS NULL;

-- 2.6 Cat_Gerencias_Activos -> Cat_Subdirecciones (Fk_Id_CatSubDirec debe existir)
SELECT g.Id_CatGeren, g.Fk_Id_CatSubDirec
FROM Cat_Gerencias_Activos g
LEFT JOIN Cat_Subdirecciones s ON s.Id_CatSubDirec = g.Fk_Id_CatSubDirec
WHERE s.Id_CatSubDirec IS NULL;

-- 2.7 Info_Personal -> Cat_Regimenes_Trabajo (validar solo si NO es NULL)
SELECT i.Id_InfoPersonal, i.Fk_Id_CatRegimen
FROM Info_Personal i
LEFT JOIN Cat_Regimenes_Trabajo r ON r.Id_CatRegimen = i.Fk_Id_CatRegimen
WHERE i.Fk_Id_CatRegimen IS NOT NULL
  AND r.Id_CatRegimen IS NULL;

-- 2.8 Info_Personal -> Cat_Puestos_Trabajo (validar solo si NO es NULL)
SELECT i.Id_InfoPersonal, i.Fk_Id_CatPuesto
FROM Info_Personal i
LEFT JOIN Cat_Puestos_Trabajo p ON p.Id_CatPuesto = i.Fk_Id_CatPuesto
WHERE i.Fk_Id_CatPuesto IS NOT NULL
  AND p.Id_CatPuesto IS NULL;

-- 2.9 Info_Personal -> Cat_Centros_Trabajo (validar solo si NO es NULL)
SELECT i.Id_InfoPersonal, i.Fk_Id_CatCT
FROM Info_Personal i
LEFT JOIN Cat_Centros_Trabajo ct ON ct.Id_CatCT = i.Fk_Id_CatCT
WHERE i.Fk_Id_CatCT IS NOT NULL
  AND ct.Id_CatCT IS NULL;

-- 2.10 Info_Personal -> Cat_Departamentos (validar solo si NO es NULL)
SELECT i.Id_InfoPersonal, i.Fk_Id_CatDep
FROM Info_Personal i
LEFT JOIN Cat_Departamentos d ON d.Id_CatDep = i.Fk_Id_CatDep
WHERE i.Fk_Id_CatDep IS NOT NULL
  AND d.Id_CatDep IS NULL;

-- 2.11 Info_Personal -> Cat_Regiones_Trabajo (validar solo si NO es NULL)
SELECT i.Id_InfoPersonal, i.Fk_Id_CatRegion
FROM Info_Personal i
LEFT JOIN Cat_Regiones_Trabajo rg ON rg.Id_CatRegion = i.Fk_Id_CatRegion
WHERE i.Fk_Id_CatRegion IS NOT NULL
  AND rg.Id_CatRegion IS NULL;

-- 2.12 Info_Personal -> Cat_Gerencias_Activos (validar solo si NO es NULL)
SELECT i.Id_InfoPersonal, i.Fk_Id_CatGeren
FROM Info_Personal i
LEFT JOIN Cat_Gerencias_Activos g ON g.Id_CatGeren = i.Fk_Id_CatGeren
WHERE i.Fk_Id_CatGeren IS NOT NULL
  AND g.Id_CatGeren IS NULL;

-- 2.13 Usuarios -> Info_Personal (Fk_Id_InfoPersonal debe existir)
SELECT u.Id_Usuario, u.Fk_Id_InfoPersonal
FROM Usuarios u
LEFT JOIN Info_Personal i ON i.Id_InfoPersonal = u.Fk_Id_InfoPersonal
WHERE i.Id_InfoPersonal IS NULL;

-- 2.14 Usuarios -> Cat_Roles (Fk_Rol debe existir en Cat_Roles.Id_Rol)
SELECT u.Id_Usuario, u.Fk_Rol
FROM Usuarios u
LEFT JOIN Cat_Roles r ON r.Id_Rol = u.Fk_Rol
WHERE r.Id_Rol IS NULL;

/* =====================================================================================
   3) DUPLICADOS EN CAMPOS QUE DEBERÍAN SER ÚNICOS
   (Cada query debe devolver 0 filas; si devuelve algo hay duplicados que debes depurar)
===================================================================================== */

-- 3.1 Pais.Codigo (tienes UNIQUE Uk_Codigo_Pais)
SELECT Codigo, COUNT(*) AS c
FROM Pais
GROUP BY Codigo
HAVING c > 1;

-- 3.2 Estado.Codigo (tienes UNIQUE Uk_Codigo_Estado)
SELECT Codigo, COUNT(*) AS c
FROM Estado
GROUP BY Codigo
HAVING c > 1;

-- 3.3 Cat_Centros_Trabajo.Codigo (tienes UNIQUE Uk_Codigo_CatCT)
SELECT Codigo, COUNT(*) AS c
FROM Cat_Centros_Trabajo
GROUP BY Codigo
HAVING c > 1;

-- 3.4 Usuarios.Email y Usuarios.Ficha (tienes UNIQUE en ambos)
SELECT Email, COUNT(*) AS c
FROM Usuarios
GROUP BY Email
HAVING c > 1;

SELECT Ficha, COUNT(*) AS c
FROM Usuarios
GROUP BY Ficha
HAVING c > 1;

-- 3.5 Cat_Direcciones.Clave / Cat_Subdirecciones.Clave / Cat_Gerencias_Activos.Clave
--     (OJO: tus cargas hacen NULLIF('', ''), así evitas duplicados de '' por UNIQUE)
SELECT Clave, COUNT(*) AS c
FROM Cat_Direcciones
WHERE Clave IS NOT NULL
GROUP BY Clave
HAVING c > 1;

SELECT Clave, COUNT(*) AS c
FROM Cat_Subdirecciones
WHERE Clave IS NOT NULL
GROUP BY Clave
HAVING c > 1;

SELECT Clave, COUNT(*) AS c
FROM Cat_Gerencias_Activos
WHERE Clave IS NOT NULL
GROUP BY Clave
HAVING c > 1;

/* =====================================================================================
   4) CALIDAD DE DATOS: STRINGS VACÍOS / SOLO ESPACIOS
   (Detecta “basura silenciosa”: valores '' o '   ' que luego rompen búsquedas/reportes)
===================================================================================== */

-- 4.1 Pais: Codigo y Nombre no deberían venir vacíos
SELECT *
FROM Pais
WHERE TRIM(Codigo) = '' OR TRIM(Nombre) = '';

-- 4.2 Estado: Codigo y Nombre no deberían venir vacíos
SELECT *
FROM Estado
WHERE TRIM(Codigo) = '' OR TRIM(Nombre) = '';

-- 4.3 Municipio: Nombre no debería venir vacío (Codigo puede ser NULL según tu DDL)
SELECT *
FROM Municipio
WHERE TRIM(Nombre) = '';

-- 4.4 Centros de trabajo: Codigo y Nombre no deberían venir vacíos
SELECT *
FROM Cat_Centros_Trabajo
WHERE TRIM(Codigo) = '' OR TRIM(Nombre) = '';

-- 4.5 Departamentos: Codigo y Nombre no deberían venir vacíos
SELECT *
FROM Cat_Departamentos
WHERE TRIM(Codigo) = '' OR TRIM(Nombre) = '';

-- 4.6 Usuarios: Email y Ficha no deberían venir vacíos
SELECT *
FROM Usuarios
WHERE TRIM(Email) = '' OR TRIM(Ficha) = '';

/* =====================================================================================
   5) PRE-CHECK PARA ACTIVAR UNIQUE EN Cat_Departamentos(Codigo)
   (Primero verifica duplicados; si NO hay, ya puedes crear el constraint)
===================================================================================== */
SELECT Codigo, COUNT(*) AS c
FROM Cat_Departamentos
GROUP BY Codigo
HAVING c > 1;

-- Si el query anterior devuelve 0 filas, ejecuta esto:
-- ALTER TABLE Cat_Departamentos
-- ADD CONSTRAINT Uk_Codigo_CatDep UNIQUE (Codigo);

/* =====================================================================================
   6) CHECKS EXTRA ÚTILES PARA CAPACITACIONES (cuando empieces a poblar)
===================================================================================== */

-- 6.1 Cat_Estatus_Capacitacion: valida que Es_Final solo sea 0/1 (calidad de datos)
SELECT *
FROM Cat_Estatus_Capacitacion
WHERE Es_Final NOT IN (0, 1);

-- 6.2 DatosCapacitaciones: verifica (por si algún insert posterior falla) fechas válidas
--     (Tu tabla ya tiene CHECK Fecha_Inicio <= Fecha_Fin, esto es solo para revisar)
SELECT *
FROM DatosCapacitaciones
WHERE Fecha_Inicio > Fecha_Fin;

-- 6.3 Capacitaciones_Participantes: porcentaje debe estar 0..100 (tu CHECK lo obliga)
SELECT *
FROM Capacitaciones_Participantes
WHERE PorcentajeAsistencia IS NOT NULL
  AND (PorcentajeAsistencia < 0 OR PorcentajeAsistencia > 100);

/* =====================================================================================
   FIN
===================================================================================== */

