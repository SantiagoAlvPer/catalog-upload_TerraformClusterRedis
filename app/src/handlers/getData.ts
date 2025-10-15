import { getRedisClient } from "../services/redis.js";

export const handler = async ({target}: {target: string}) => {
    const Client = await getRedisClient();
    const key = `products:${target}`;
    const existing = await Client.exists(key);
    if (!existing) {
        return { statusCode: 404, body: "Product not found" };
    }
}; 
