import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { Readable } from "stream";
import csvParser from "csv-parser";
import { getRedisClient } from "../services/redis.js";

const s3Client = new S3Client({ region: process.env.AWS_REGION || "us-east-2" });
const BUCKET_NAME = process.env.S3_BUCKET_NAME || "catalog-bucket";

interface ProductRecord {
  categoria: string;
  proveedor: string;
  servicio: string;
  plan: string;
  precio_mensual: string;
  detalles: string;
  estado: string;
}

interface LambdaEvent {
  body: string;
  isBase64Encoded?: boolean;
  headers?: Record<string, string>;
}

// Helper function to parse CSV using csv-parser
const parseCsvContent = (csvContent: string): Promise<ProductRecord[]> => {
  return new Promise((resolve, reject) => {
    const records: ProductRecord[] = [];
    const stream = Readable.from([csvContent]);
    
    stream
      .pipe(csvParser())
      .on("data", (data) => records.push(data))
      .on("end", () => resolve(records))
      .on("error", (error) => reject(error));
  });
};

export const handler = async (event: LambdaEvent) => {
  try {
    // 1. Obtener el contenido del CSV del body
    let csvContent: string;
    
    if (event.isBase64Encoded) {
      csvContent = Buffer.from(event.body, "base64").toString("utf-8");
    } else {
      csvContent = event.body;
    }

    if (!csvContent || csvContent.trim().length === 0) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "CSV content is empty or missing" }),
      };
    }

    // 2. Parsear el CSV
    const records = await parseCsvContent(csvContent);

    if (records.length === 0) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "No valid records found in CSV" }),
      };
    }

    // 3. Subir el CSV a S3
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const s3Key = `catalogs/catalog-${timestamp}.csv`;
    
    await s3Client.send(
      new PutObjectCommand({
        Bucket: BUCKET_NAME,
        Key: s3Key,
        Body: csvContent,
        ContentType: "text/csv",
      })
    );

    console.log(`CSV uploaded to S3: ${s3Key}`);

    // 4. Conectar a Redis
    const redisClient = await getRedisClient();

    // 5. Reemplazar completamente los datos en Redis
    // Primero, obtener todas las keys existentes del catálogo
    const existingKeys = await redisClient.keys("products:*");
    
    // Eliminar todas las keys existentes si hay
    if (existingKeys.length > 0) {
      await redisClient.del(existingKeys);
      console.log(`Deleted ${existingKeys.length} existing product keys from Redis`);
    }

    // 6. Insertar los nuevos productos en Redis
    const pipeline = redisClient.multi();
    
    for (const record of records) {
      // Usar un identificador único, puede ser combinación de campos o un ID si existe
      const productId = `${record.categoria}-${record.proveedor}-${record.servicio}`.replace(/\s+/g, "-").toLowerCase();
      const key = `products:${productId}`;
      
      // Guardar como hash en Redis
      pipeline.hSet(key, {
        categoria: record.categoria || "",
        proveedor: record.proveedor || "",
        servicio: record.servicio || "",
        plan: record.plan || "",
        precio_mensual: record.precio_mensual || "",
        detalles: record.detalles || "",
        estado: record.estado || "Activo",
      });
    }

    await pipeline.exec();
    console.log(`Inserted ${records.length} products into Redis`);

    // 7. Retornar respuesta exitosa
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: "Catalog updated successfully",
        s3Location: `s3://${BUCKET_NAME}/${s3Key}`,
        productsUpdated: records.length,
        productsDeleted: existingKeys.length,
      }),
    };
  } catch (error) {
    console.error("Error updating catalog:", error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        error: "Failed to update catalog",
        details: error instanceof Error ? error.message : String(error),
      }),
    };
  }
};