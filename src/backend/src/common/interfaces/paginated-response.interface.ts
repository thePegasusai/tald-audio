/**
 * Interface defining metadata for paginated responses, including page information,
 * item counts, and navigation flags.
 * @interface PaginationMeta
 */
export interface PaginationMeta {
  /**
   * Current page number (1-based indexing)
   * @type {number}
   */
  page: number;

  /**
   * Number of items requested per page
   * @type {number}
   */
  take: number;

  /**
   * Total number of items in the current page
   * @type {number}
   */
  itemCount: number;

  /**
   * Total number of available pages
   * @type {number}
   */
  pageCount: number;

  /**
   * Flag indicating whether a previous page exists
   * @type {boolean}
   */
  hasPreviousPage: boolean;

  /**
   * Flag indicating whether a next page exists
   * @type {boolean}
   */
  hasNextPage: boolean;
}

/**
 * Generic interface for paginated API responses, providing type-safe access
 * to paginated data collections.
 * @interface PaginatedResponse<T>
 * @template T - The type of items contained in the paginated response
 */
export interface PaginatedResponse<T> {
  /**
   * Array of paginated items of type T
   * @type {T[]}
   */
  data: T[];

  /**
   * Metadata containing pagination information and navigation flags
   * @type {PaginationMeta}
   */
  meta: PaginationMeta;
}