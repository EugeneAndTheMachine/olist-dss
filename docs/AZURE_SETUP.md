# Hướng dẫn set up data lake trên Azure (Azure for Students)

> Mục tiêu: tạo một **Storage account ADLS Gen2** trên Azure làm data lake (tầng Landing/Bronze) cho pipeline,
> thay cho Azurite chạy local. Code không phải sửa, chỉ đổi `AZURE_STORAGE_CONNECTION_STRING` trong `.env`.
>
> - Thời gian: khoảng 20–30 phút.
> - Chi phí: vài cent trong $100 credit (dữ liệu ~150 MB).
> - Chỉ **1 người** (chủ subscription) làm phần 1–5; các thành viên khác chỉ cần phần 6.
> - Chưa cần Azure thật thì bỏ qua file này: `make up` đã chạy Azurite (giả lập Azure) trên máy, xem `docs/SETUP.md` mục 5.

## Mục lục

0. [Kiến trúc & các khái niệm](#0-kiến-trúc--các-khái-niệm)
1. [Kích hoạt Azure for Students](#1-kích-hoạt-azure-for-students)
2. [Tìm region được phép dùng](#2-tìm-region-được-phép-dùng)
3. [Tạo Resource group](#3-tạo-resource-group)
4. [Tạo Storage account (ADLS Gen2)](#4-tạo-storage-account-adls-gen2)
5. [Lấy connection string](#5-lấy-connection-string)
6. [Kết nối pipeline với Azure](#6-kết-nối-pipeline-với-azure)
7. [Kiểm tra kết quả](#7-kiểm-tra-kết-quả)
8. [Kiểm soát chi phí](#8-kiểm-soát-chi-phí)
9. [Quay về Azurite / dọn dẹp](#9-quay-về-azurite--dọn-dẹp)
10. [Cách làm bằng Azure CLI (thay cho Portal)](#10-cách-làm-bằng-azure-cli-thay-cho-portal)
11. [Xử lý sự cố](#11-xử-lý-sự-cố)

---

## 0. Kiến trúc & các khái niệm

```
data/raw, Kaggle, holidays
        │  make ingest (upload_to_lake.py)
        ▼
Azure Storage account  olistlake<xxx>          ← phần 4
  └─ container  olist-lake                     ← upload_to_lake tự tạo
       └─ landing/<source>/<dataset>/extract_date=YYYY-MM-DD/<file>
        │  make load-raw (load_raw.py)
        ▼
PostgreSQL (local, trong Docker): raw → stg → dw → bi
```

| Khái niệm Azure | Tương đương MinIO / S3 | Trong dự án |
| --- | --- | --- |
| Subscription | Tài khoản billing | Azure for Students ($100) |
| Resource group | Thư mục gom tài nguyên | `rg-olist-dss`, xoá nó là xoá hết |
| Storage account | Server MinIO | `olistlake<xxx>` |
| Container | Bucket | `olist-lake` |
| Blob | Object | Từng file CSV / JSON |
| Hierarchical namespace (ADLS Gen2) | (không có) | Thư mục thật, đúng nghĩa data lake |
| Connection string | Endpoint + access key | Biến `AZURE_STORAGE_CONNECTION_STRING` |
| SAS (Shared Access Signature) | Access key giới hạn quyền, có hạn | Dùng để chia cho thành viên |

---

## 1. Kích hoạt Azure for Students

1. Mở https://azure.microsoft.com/free/students → **Start free**.
2. Đăng nhập bằng **email trường** (hoặc tài khoản Microsoft rồi xác minh email trường).
3. Điền thông tin, xác minh số điện thoại. **Không cần thẻ tín dụng.**
4. Xong sẽ vào được https://portal.azure.com. Kiểm tra: ô tìm kiếm trên cùng → gõ **Subscriptions** → thấy subscription **Azure for Students**, trạng thái *Active*.
5. Xem số credit còn lại: Portal → tìm **Education** → **Overview** (khung *Credit*); hoặc mở subscription → **Overview**.

> Credit: $100, hạn 12 tháng; hết credit thì tài nguyên bị tắt, **không tự trừ tiền**.

---

## 2. Tìm region được phép dùng

Subscription sinh viên có policy chỉ cho tạo tài nguyên ở **một số region** (mỗi tài khoản có thể khác nhau). Kiểm tra trước để khỏi bị lỗi `RequestDisallowedByAzure` ở bước 4.

1. Portal → tìm **Policy** → menu trái **Assignments**.
2. Mở assignment tên **Allowed resource deployment regions** (đôi khi tên là `sys.regionrestriction`).
3. Tab **Parameters** → xem danh sách *Allowed locations*.
4. Chọn một region trong danh sách, ưu tiên gần Việt Nam: `southeastasia` (Singapore) → `eastasia` (Hong Kong) → `japaneast` / `koreacentral` → `australiaeast`.

> Không thấy assignment nào thì subscription không bị giới hạn; chọn **Southeast Asia**.
>
> **Kiểm tra chắc chắn mà không tạo gì**: ở bước 4, điền form với region đã chọn rồi bấm tới tab **Review + create**. Portal chạy validation, có kiểm tra cả policy. Thấy **Validation passed** thì region dùng được; thấy `RequestDisallowedByAzure` / *Validation failed* thì bấm *Previous* và đổi region. Chưa bấm **Create** thì chưa có tài nguyên nào được tạo.
>
> Lưu ý: nhiều người dùng Azure for Students báo **East Asia** bị chặn ở subscription của họ, có người lại thấy East Asia trong danh sách cho phép. Vì vậy phải xem danh sách của chính subscription mình, không suy ra từ tài khoản người khác.
>
> Bằng CLI (xem mục 10): `az policy assignment list --query "[].{name:displayName, params:parameters}" -o json` → tìm `listOfAllowedLocations`.

Ghi lại region đã chọn, dùng cho bước 3 và 4.

---

## 3. Tạo Resource group

1. Portal → tìm **Resource groups** → **+ Create**.
2. Điền:

   | Trường | Giá trị |
   | --- | --- |
   | Subscription | Azure for Students |
   | Resource group | `rg-olist-dss` |
   | Region | region ở bước 2 |

3. **Review + create** → **Create**.

---

## 4. Tạo Storage account (ADLS Gen2)

Portal → tìm **Storage accounts** → **+ Create**. Đi lần lượt từng tab:

### Tab Basics

| Trường | Giá trị | Ghi chú |
| --- | --- | --- |
| Subscription | Azure for Students | |
| Resource group | `rg-olist-dss` | |
| Storage account name | `olistlake<viết-tắt>`, vd. `olistlakenhom4` | 3–24 ký tự, **chỉ chữ thường và số**, duy nhất toàn Azure |
| Region | region ở bước 2 | |
| Primary service | **Azure Blob Storage or Azure Data Lake Storage Gen2** | |
| Performance | **Standard** | Premium đắt hơn nhiều |
| Redundancy | **Locally-redundant storage (LRS)** | Rẻ nhất, đủ cho bài tập |

### Tab Advanced

| Trường | Giá trị | Ghi chú |
| --- | --- | --- |
| Require secure transfer for REST API operations | ✅ Bật | Chỉ HTTPS |
| Allow enabling anonymous access on individual containers | ❌ Tắt | Không cho truy cập công khai |
| Enable storage account key access | ✅ Bật | Code dùng connection string có key/SAS |
| Minimum TLS version | Version 1.2 | |
| **Hierarchical Namespace → Enable hierarchical namespace** | ✅ **Bật** | Biến account thành **ADLS Gen2**. **Không đổi lại được** sau khi tạo |
| Access tier | **Hot** | Dữ liệu đọc thường xuyên |

### Tab Networking

| Trường | Giá trị |
| --- | --- |
| Network access | **Enable public access from all networks** (để 4 máy ở 4 nơi đều kết nối được) |
| Routing preference | Microsoft network routing (mặc định) |

### Tab Data protection

Để mặc định (soft delete 7 ngày) cũng được. Muốn xoá thử nghiệm cho gọn thì **tắt** *Enable soft delete for blobs* và *Enable soft delete for containers*.

### Tab Encryption, Tags

Để mặc định. (Tuỳ chọn) Tag `project = olist-dss` để dễ lọc chi phí.

### Review + create

Bấm **Create**, chờ khoảng 30 giây → **Go to resource**.

> **Vì sao chọn ADLS Gen2 thay vì Blob thường?** Cùng giá lưu trữ, nhưng có thư mục thật (đổi tên/xoá thư mục là thao tác nguyên tử, phân quyền ACL theo thư mục) — đây là dịch vụ "data lake" chính thức của Azure, dùng để trình bày tầng Landing/Bronze trong báo cáo.
> SDK Blob mà code đang dùng chạy được trên cả hai loại.

---

## 5. Lấy connection string

Chọn **A** nếu chỉ máy bạn dùng; chọn **B** để chia cho thành viên khác hoặc máy chạy Airflow.

### A. Access key (toàn quyền — chỉ chủ subscription giữ)

1. Storage account → menu trái **Security + networking → Access keys**.
2. Ở **key1** → **Connection string** → **Show** → bấm nút copy.
3. Dạng:

   ```
   DefaultEndpointsProtocol=https;AccountName=olistlakenhom4;AccountKey=xxxx...==;EndpointSuffix=core.windows.net
   ```

> ⚠️ Key này có toàn quyền (kể cả xoá account data). **Không** gửi vào nhóm chat, **không** commit, **không** chụp màn hình đưa vào báo cáo.
> Lỡ lộ: Access keys → **Rotate key** cho key1 → mọi connection string cũ hết hiệu lực.

### B. SAS (giới hạn quyền + có hạn — để chia cho nhóm)

1. Storage account → **Security + networking → Shared access signature**.
2. Chọn đúng như sau:

   | Trường | Chọn |
   | --- | --- |
   | Allowed services | ✅ **Blob** (bỏ File, Queue, Table) |
   | Allowed resource types | ✅ **Container**, ✅ **Object** (bỏ Service) |
   | Allowed permissions | ✅ **Read**, ✅ **Write**, ✅ **List**, ✅ **Add**, ✅ **Create** — **bỏ Delete**, Update, Process, Permanent delete... (landing là bất biến, không ai được xoá) |
   | Blob versioning permissions | bỏ trống |
   | Start and expiry date/time | Start: hôm nay · End: **sau ngày nộp bài** (vd. 30/11/2026) |
   | Allowed IP addresses | để trống |
   | Allowed protocols | **HTTPS only** |
   | Signing key | key1 |

3. **Generate SAS and connection string**.
4. Copy ô **Connection string** (không phải ô *SAS token*). Dạng:

   ```
   BlobEndpoint=https://olistlakenhom4.blob.core.windows.net/;QueueEndpoint=...;SharedAccessSignature=sv=2022-11-02&ss=b&srt=co&sp=rwlac&se=2026-11-30T...&sig=...
   ```

5. Gửi cho thành viên qua tin nhắn riêng (không đăng lên repo, issue hay nhóm công khai).

> Thu hồi SAS trước hạn: **Rotate key1** (mọi SAS ký bằng key1 hết hiệu lực) rồi tạo SAS mới.

---

## 6. Kết nối pipeline với Azure

Làm trên **mỗi máy** muốn dùng Azure thật.

1. Mở `.env` ở thư mục gốc repo, thay dòng `AZURE_STORAGE_CONNECTION_STRING` (của Azurite) bằng connection string ở bước 5. Viết **trên một dòng**, không có ngoặc kép, không có comment phía sau:

   ```
   AZURE_STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=olistlakenhom4;AccountKey=xxxx==;EndpointSuffix=core.windows.net
   LAKE_CONTAINER=olist-lake
   ```

2. PostgreSQL vẫn chạy local: `make up` (Azurite cũng lên nhưng không được dùng, không sao).
3. **Chỉ 1 máy** đẩy dữ liệu lên lake:

   ```bash
   make ingest
   ```

   Log mong đợi: `Upload olist-lake/landing/...` rồi `Xong: N file mới, 0 file đã có`. Chạy lại → `0 file mới, N file đã có` (landing bất biến).

4. **Mọi máy** (kể cả máy ở bước 3) nạp từ lake vào PostgreSQL của mình:

   ```bash
   make load-raw
   ```

> Vì sao chỉ 1 máy `make ingest`? Mỗi lần ingest ở một ngày khác tạo thêm thư mục `extract_date=<ngày>` chứa bản sao toàn bộ file, và `load_raw` sẽ nạp cả bản sao đó vào `raw`.
> Staging có dedup theo natural key nên kết quả `stg/dw` không sai, nhưng `raw` phình ra và log khó đọc.

**Airflow** (máy demo): không cần chỉnh gì thêm. Container đọc cùng `.env`; với connection string Azure thật, code không đổi host (việc đổi `127.0.0.1` → `azurite` chỉ áp dụng cho Azurite).

---

## 7. Kiểm tra kết quả

**Trên Portal**: Storage account → **Data storage → Containers** → `olist-lake` → `landing` → `kaggle`, `holidays`, `manual` → `.../extract_date=YYYY-MM-DD/` → các file CSV/JSON.

**Bằng Python** (đếm file trên lake):

```bash
uv run python -c "from ingestion.config import get_settings; from ingestion.lake import container_client, list_keys; print(len(list_keys(container_client(get_settings()), 'landing/')))"
```

**Trong PostgreSQL** (DBeaver hoặc `docker compose exec postgres psql -U olist -d olist_dw`):

```sql
select count(*) from raw.orders;                                    -- 99 441
select distinct _source_file from raw.orders;                       -- landing/kaggle/brazilian-ecommerce/extract_date=.../olist_orders_dataset.csv
select step, status, rows_out, message from meta.etl_run_log order by log_id desc limit 20;
```

**Bằng Azure Storage Explorer** (GUI, tiện chụp hình cho báo cáo):

1. Cài: `winget install Microsoft.Azure.StorageExplorer` hoặc https://azure.microsoft.com/products/storage/storage-explorer/
2. **Connect** (biểu tượng phích cắm) → **Storage account or service** → **Connection string** → dán connection string → **Next → Connect**.
3. Cùng app đó xem được Azurite local: **Connect → Local storage emulator**.

---

## 8. Kiểm soát chi phí

Ước tính cho dự án:

| Hạng mục | Mức dùng | Chi phí ước tính |
| --- | --- | --- |
| Lưu trữ Hot LRS | ~0.15 GB | < $0.01 / tháng |
| Ghi (upload) | vài chục file / lần ingest | ~ $0 |
| Đọc + egress | ~150 MB mỗi lần `load_raw` × 4 máy | Nằm trong 100 GB egress miễn phí / tháng |

Đặt cảnh báo cho yên tâm:

1. Portal → tìm **Cost Management** → **Budgets** → **+ Add**.
2. Scope: subscription Azure for Students · Name: `olist-budget` · Reset period: Monthly · Amount: **5** (USD).
3. **Alert conditions**: Actual 50% và 90% → email của bạn → **Create**.
4. Xem chi phí thực tế: **Cost Management → Cost analysis**, lọc theo resource group `rg-olist-dss`.

---

## 9. Quay về Azurite / dọn dẹp

**Quay về Azurite** (dev offline): copy lại dòng `AZURE_STORAGE_CONNECTION_STRING` từ `.env.example` vào `.env`, rồi `make ingest` → `make load-raw`.

**Xoá toàn bộ sau khi xong môn** (không thể khôi phục):

1. Portal → **Resource groups** → `rg-olist-dss` → **Delete resource group**.
2. Gõ lại tên `rg-olist-dss` để xác nhận → **Delete**.

---

## 10. Cách làm bằng Azure CLI (thay cho Portal)

Cài CLI: `winget install Microsoft.AzureCLI` → mở lại terminal → `az --version`. Lệnh dưới viết cho Git Bash.

```bash
az login                                            # mở trình duyệt, đăng nhập email trường
az account show --query "{name:name, state:state}"  # phải là Azure for Students, Enabled

# Bước 2: xem region được phép
az policy assignment list --query "[?contains(displayName, 'region')].parameters" -o json

# Đặt biến (sửa tên account cho duy nhất)
RG=rg-olist-dss
LOC=southeastasia
SA=olistlakenhom4

# Bước 3 + 4: resource group + storage account ADLS Gen2
az group create -n $RG -l $LOC
az storage account create -n $SA -g $RG -l $LOC \
  --sku Standard_LRS --kind StorageV2 --access-tier Hot \
  --hns true --https-only true --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# Bước 5A: connection string có access key
az storage account show-connection-string -n $SA -g $RG -o tsv

# Bước 5B: SAS cho thành viên (Blob; Container+Object; read/write/list/add/create; HTTPS; hết hạn 30/11/2026)
KEY=$(az storage account keys list -n $SA -g $RG --query "[0].value" -o tsv)
SAS=$(az storage account generate-sas --account-name $SA --account-key "$KEY" \
  --services b --resource-types co --permissions rwlac \
  --expiry 2026-11-30T23:59Z --https-only -o tsv)
echo "BlobEndpoint=https://$SA.blob.core.windows.net/;SharedAccessSignature=$SAS"

# Kiểm tra sau khi make ingest
az storage blob list --account-name $SA --account-key "$KEY" -c olist-lake --prefix landing/ --query "[].name" -o tsv

# Dọn dẹp
az group delete -n $RG --yes
```

---

## 11. Xử lý sự cố

| Triệu chứng | Nguyên nhân / cách xử lý |
| --- | --- |
| `RequestDisallowedByAzure` khi tạo resource group / storage account | Region không nằm trong danh sách cho phép → làm lại bước 2 và chọn region khác. Bị chặn ở mọi region → liên hệ Azure support |
| `The storage account named ... is already taken` | Tên phải duy nhất toàn Azure → thêm số / chữ viết tắt khác |
| `AuthenticationFailed` / `Server failed to authenticate the request` | Copy thiếu ký tự connection string; key đã bị rotate; SAS hết hạn; đồng hồ máy lệch giờ (bật *Set time automatically* trong Windows) |
| `AuthorizationPermissionMismatch` | SAS thiếu quyền: cần Blob + Container/Object + `rwlac` (bước 5B) |
| `ContainerNotFound` khi `make load-raw` | Chưa có máy nào chạy `make ingest` lên account này |
| `ResourceExistsError` / `BlobAlreadyExists` khi upload | Đúng thiết kế: landing bất biến, không ghi đè. `upload_to_lake` đã kiểm tra trước nên thường không gặp; nếu gặp thì 2 máy đang upload cùng lúc → chạy lại |
| `This request is not authorized to perform this operation` (403) dù key đúng | Networking đang để *Selected networks* → bước 4 tab Networking chọn *Enable public access from all networks* |
| Kết nối chậm / timeout | Kiểm tra region (nên Southeast Asia / East Asia); mạng trường chặn cổng 443 ra ngoài → thử mạng khác |
| `.env` có connection string nhưng code vẫn ghi vào Azurite | Biến môi trường của terminal ghi đè `.env` → `unset AZURE_STORAGE_CONNECTION_STRING` hoặc mở terminal mới |
| Hết credit / subscription *Disabled* | Kiểm tra số dư (bước 1.5); quay về Azurite (bước 9) |
