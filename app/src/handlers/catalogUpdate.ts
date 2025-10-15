import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { Readable } from "stream";
import csvParser from "csv-parser";
import { getRedisClient } from "../services/redis.js";

const s3Client = new S3Client({
  region: process.env.AWS_REGION || "us-east-2",
});
const BUCKET_NAME = process.env.S3_BUCKET || "";

interface ProductRecord {
  categoria: string;
  proveedor: string;
  servicio: string;
  plan: string;
  precio_mensual: string;
  detalles: string;
  estado: string;
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

export const handler = async (
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
  console.log("Event received:", JSON.stringify(event, null, 2));

  try {
    // 1. Obtener el contenido del CSV del body
    if (!event.body) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ error: "CSV content is empty or missing" }),
      };
    }

    let csvContent: string;

    if (event.isBase64Encoded) {
      csvContent = Buffer.from(event.body, "base64").toString("utf-8");
    } else {
      csvContent = event.body;
    }

    console.log("CSV content length:", csvContent.length);

    // 2. Parsear el CSV
    const records = await parseCsvContent(csvContent);

    console.log(`Parsed ${records.length} records from CSV`);

    if (records.length === 0) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
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
        Metadata: {
          uploadedAt: new Date().toISOString(),
          recordCount: records.length.toString(),
        },
      })
    );

    console.log(`CSV uploaded to S3: ${BUCKET_NAME}/${s3Key}`);

    // 4. Conectar a Redis
    const redisClient = await getRedisClient();

    // 5. Reemplazar completamente los datos en Redis
    console.log("Cleaning existing products from Redis...");

    const existingKeys = await redisClient.keys("catalog:product:*");

    if (existingKeys.length > 0) {
      await redisClient.del(existingKeys);
      console.log(
        `Deleted ${existingKeys.length} existing product keys from Redis`
      );
    }

    // 6. Insertar los nuevos productos en Redis usando pipeline
    console.log("Inserting new products into Redis...");

    const pipeline = redisClient.multi();

    records.forEach((record, index) => {
      const key = `catalog:product:${index + 1}`;

      pipeline.hSet(key, {
        categoria: record.categoria || "",
        proveedor: record.proveedor || "",
        servicio: record.servicio || "",
        plan: record.plan || "",
        precio_mensual: record.precio_mensual || "",
        detalles: record.detalles || "",
        estado: record.estado || "Activo",
      });
    });

    // Guardar metadata del catálogo
    pipeline.hSet("catalog:metadata", {
      lastUpdate: new Date().toISOString(),
      totalProducts: records.length.toString(),
      s3Key: s3Key,
      s3Bucket: BUCKET_NAME,
    });

    await pipeline.exec();
    console.log(`Successfully inserted ${records.length} products into Redis`);

    // 7. Retornar respuesta exitosa
    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        message: "Catálogo actualizado exitosamente",
        stats: {
          s3Location: `s3://${BUCKET_NAME}/${s3Key}`,
          productsUpdated: records.length,
          productsDeleted: existingKeys.length,
          timestamp: new Date().toISOString(),
        },
      }),
    };
  } catch (error) {
    console.error("Error updating catalog:", error);

    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        error: "Error al actualizar el catálogo",
        details: error instanceof Error ? error.message : String(error),
      }),
    };
  }
};
