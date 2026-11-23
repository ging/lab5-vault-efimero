-- Se ejecuta una sola vez, al crear el volumen de Postgres por primera vez
-- (mecanismo estándar de la imagen oficial: docker-entrypoint-initdb.d).
-- Solo sirve para tener algo real que consultar con las credenciales efímeras.

CREATE TABLE IF NOT EXISTS inventario (
    id SERIAL PRIMARY KEY,
    articulo TEXT NOT NULL,
    cantidad INTEGER NOT NULL
);

INSERT INTO inventario (articulo, cantidad) VALUES
    ('teclados', 12),
    ('monitores', 7),
    ('portatiles', 25);
