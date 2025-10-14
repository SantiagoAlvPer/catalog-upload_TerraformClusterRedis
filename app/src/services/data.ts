import { faker } from "@faker-js/faker";

export const generateFakeProducts = (): Promise<Record<string, any>> => {
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve({
        categoria: faker.commerce.department(),
        proveedor: faker.company.name(),
        servicio: faker.commerce.productName(),
        plan: faker.commerce.productAdjective(),
        precio_mensual: faker.commerce.price({
          min: 5,
          max: 100,
          dec: 2,
          symbol: "$",
        }),
        detalles: faker.commerce.productDescription(),
        estado: "Activo",
      });
    }, 5000);
  });
};
