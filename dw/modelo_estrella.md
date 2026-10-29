# Modelo estrella

Generado por `run_sql.py` a partir de las tablas de `warehouse.duckdb`.

```mermaid
erDiagram
    dim_channel ||--o{ fact_nps : "channel_key"
    dim_channel ||--o{ fact_payment : "channel_key"
    dim_channel ||--o{ fact_sales : "channel_key"
    dim_channel ||--o{ fact_sales_item : "channel_key"
    dim_channel ||--o{ fact_shipment : "channel_key"
    dim_channel ||--o{ fact_web_session : "channel_key"
    dim_customer ||--o{ fact_nps : "customer_key"
    dim_customer ||--o{ fact_payment : "customer_key"
    dim_customer ||--o{ fact_sales : "customer_key"
    dim_customer ||--o{ fact_sales_item : "customer_key"
    dim_customer ||--o{ fact_shipment : "customer_key"
    dim_customer ||--o{ fact_web_session : "customer_key"
    dim_date ||--o{ fact_nps : "date_key"
    dim_date ||--o{ fact_payment : "date_key"
    dim_date ||--o{ fact_sales : "date_key"
    dim_date ||--o{ fact_sales_item : "date_key"
    dim_date ||--o{ fact_shipment : "date_key"
    dim_date ||--o{ fact_web_session : "date_key"
    dim_product ||--o{ fact_sales_item : "product_key"
    dim_province ||--o{ fact_payment : "province_key"
    dim_province ||--o{ fact_sales : "province_key"
    dim_province ||--o{ fact_sales_item : "province_key"
    dim_province ||--o{ fact_shipment : "province_key"
    dim_store ||--o{ fact_payment : "store_key"
    dim_store ||--o{ fact_sales : "store_key"
    dim_store ||--o{ fact_sales_item : "store_key"
    dim_store ||--o{ fact_shipment : "store_key"
    fact_sales ||--o{ fact_payment : "order_id"
    fact_sales ||--o{ fact_sales_item : "order_id"
    fact_sales ||--o{ fact_shipment : "order_id"
    dim_channel {
        INTEGER channel_key PK
        INTEGER channel_id
        VARCHAR code
        VARCHAR name
    }
    dim_customer {
        INTEGER customer_key PK
        INTEGER customer_id
        VARCHAR first_name
        VARCHAR last_name
        VARCHAR full_name
        VARCHAR status
        TIMESTAMP created_at
    }
    dim_date {
        INTEGER date_key PK
        DATE date
        INTEGER year
        INTEGER quarter
        INTEGER month
        VARCHAR month_name
        VARCHAR year_month
        INTEGER day
        INTEGER day_of_week
        VARCHAR day_name
        BOOLEAN is_weekend
    }
    dim_product {
        INTEGER product_key PK
        INTEGER product_id
        VARCHAR sku
        VARCHAR name
        VARCHAR category
        VARCHAR family
        DECIMAL list_price
    }
    dim_province {
        INTEGER province_key PK
        INTEGER province_id
        VARCHAR name
        VARCHAR code
    }
    dim_store {
        INTEGER store_key PK
        INTEGER store_id
        VARCHAR name
        VARCHAR city
        VARCHAR province_name
    }
    fact_nps {
        BIGINT nps_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        TIMESTAMP responded_at
        INTEGER score
        VARCHAR nps_category
        INTEGER nps_value
        VARCHAR comment
    }
    fact_payment {
        BIGINT payment_id PK
        BIGINT order_id FK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        VARCHAR method
        VARCHAR status
        BOOLEAN is_collected
        TIMESTAMP paid_at
        VARCHAR transaction_ref
        DECIMAL amount
    }
    fact_sales {
        BIGINT order_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        TIMESTAMP order_date
        VARCHAR status
        BOOLEAN is_sale
        DECIMAL subtotal
        DECIMAL tax_amount
        DECIMAL shipping_fee
        DECIMAL total_amount
    }
    fact_sales_item {
        BIGINT order_item_id PK
        BIGINT order_id FK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        INTEGER product_key FK
        VARCHAR status
        BOOLEAN is_sale
        INTEGER quantity
        DECIMAL unit_price
        DECIMAL discount_amount
        DECIMAL line_total
    }
    fact_shipment {
        BIGINT shipment_id PK
        BIGINT order_id FK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        VARCHAR carrier
        VARCHAR tracking_number
        VARCHAR status
        TIMESTAMP order_date
        TIMESTAMP shipped_at
        TIMESTAMP delivered_at
        DECIMAL days_in_transit
        DECIMAL days_to_delivery
    }
    fact_web_session {
        BIGINT session_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        TIMESTAMP started_at
        TIMESTAMP ended_at
        VARCHAR source
        VARCHAR device
        BOOLEAN is_anonymous
        VARCHAR active_user_id
        INTEGER duration_seconds
    }
```
