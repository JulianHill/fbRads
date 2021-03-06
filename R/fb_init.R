## we build the functions to support one given version of the API
## so the users should not be able to override that
fbad_api_version <- 2.3


#' Get versioned base url
#' @param version the version for which a base url is being generated
#' @return character URL with trailing slash
#' @keywords internal
fbad_get_baseurl <- function() {
  paste(
      'https://graph.facebook.com',
      paste0('v', fbad_api_version),
      '', sep = '/')

}


#' Run basic checks on curl get/post parameters
#' @param params named list of parameters to GET/POST
#' @return list if OK, error if not
#' @keywords internal
fbad_check_curl_params <- function(params){

  ## Length check
  if (length(params) == 0) {
    stop("No parameters to get or set, pls debug this code")
  }

  ## Names check
  if (any(is.null(names(params)))) {
      stop("Parameters missing field names, expecting 'field = value'")
  }
  if (!"access_token" %in% names(params)) {
      stop("access_token missing")
  }

  ## Values check (not required)
  if (any(as.vector(unlist(params)) %in% c(NA, NULL))) {
      stop("NA or NULL values not allowed in cURL request")
  }

  ## Return params if all OK
  params

}


#' Get results of a synchronous query from FB graph API
#' @param path API request path (i.e. endpoint)
#' @param method HTTP request type (e.g. GET or POST or DELETE)
#' @param params a name-value list of form parameters for API query
#' @param debug print debug messages by calling Curl verbosely
#' @return json object containing results
#' @keywords internal
fbad_request <- function(path, method = c('GET', 'POST', 'DELETE'), params, debug = FALSE) {

    method <- match.arg(method)

    ## check that params meet certain standards
    params <- fbad_check_curl_params(params)

    ## get body
    b = basicTextGatherer()

    ## get headers
    h = basicHeaderGatherer()

    ## debug
    if (debug) {
        print(params)
    }

    ## query
    curlres <- tryCatch(res <- do.call(what = paste0(
                                           ifelse(method == 'GET', 'get', 'post'),
                                           'Form'),
                                       args = list(
                                           uri     = paste0(fbad_get_baseurl(), path),
                                           .params = params,
                                           .opts = curlOptions(
                                               headerfunction = h$update,
                                               verbose = debug,
                                               writefunc = b$update))),
                        error = function(e) e)

    ## remove token from params if printed for debugging purposes
    params$token <- params$access_token <- NULL

    ## Curl error handling
    if (inherits(curlres, 'error')) {
        res <- curlres
    }

    ## Response error handling
    if (inherits(res, 'error')) {
        flog.error(paste('URL: ', paste0(fbad_get_baseurl(), path)))
        flog.error(paste('Method: ', method))
        flog.error(paste('Params: ', paste(capture.output(str(params)), collapse = '\n')))
        stop(paste(
            ifelse(inherits(curlres, 'error'),
                   'This is a bug in the fbRads package. Please report on GitHub:',
                   'FB query failed:'),
            res$message))
    }

    ## return value
    res     <- b$value()
    headers <- as.list(h$value())

    ## Response code error handling
    if (headers$status != '200') {
        flog.error(paste('URL: ', paste0(fbad_get_baseurl(), path)))
        flog.error(paste('Method: ', method))
        flog.error(paste('Params: ', paste(capture.output(str(params)), collapse = '\n')))
        flog.error(paste('Header:', toJSON(headers)))
        flog.error(paste('Body:', res))
        if (!inherits(tryCatch(fromJSON(res), error = function(e) e), 'error') &&
            !is.null(fromJSON(res))) {
            stop(fromJSON(res)$error$message)
        } else {
            stop('Some critical FB query error here.')
        }
    }

    ## return
    res

}


#' Get details for a Facebook Ads Account
#' @references \url{https://developers.facebook.com/docs/marketing-api/adaccount/v2.3}
#' @param accountid Ads account graph object id
#' @param token FB Ads API token
#' @return list(s) containing account details
#' @export
fbad_get_adaccount_details  <- function(accountid, token){

    ## Check if accountid is a vector
    if (length(accountid) > 1)
        lapply(accountid, fbad_get_adaccount_details)

    ## Define which fields to get
    scope <- paste(
        c('name', 'account_id', 'account_status',
          'age', 'amount_spent', 'balance', 'capabilities',
          'daily_spend_limit', 'end_advertiser', 'funding_source',
          'spend_cap', 'timezone_id', 'users'),
        collapse = ',')

    ## Get account details
    account_details <-
        fbad_request(
            path   = paste0('act_', accountid, '/'),
            method = 'GET',
            params = list(
                access_token = token,
                fields       = scope)
            )

    fromJSON(account_details)

}


#' Initiate Facebook Account with OAuth token
#'
#' If you do not have a token, then register an (e.g. "Website") application at \url{https://developers.facebook.com/apps} and make a note of your "App ID" and "App Secret" at the "Dashboard" of your application. Then go to "Settings", click on "Add Platform", then "Website" and paste \code{http://localhost:1410} as the "Site URL". Save, and then run the below example R commands to get your token. Please note that your app needs access to your ads as well, see \url{https://developers.facebook.com/docs/marketing-api/access} for more details.
#' @param accountid Facebook Ad account id without the \code{act_} prefix
#' @param token Facebook OAuth token as a string
#' @return list containing versioned base URL and relevant API parameters
#' @export
#' @examples \dontrun{
#' ## You can generate a token for future use with the help of `httr`, e.g.
#' library(httr)
#' app <- oauth_app("facebook", your_app_id,  your_app_secret)
#' oauth2.0_token(oauth_endpoints("facebook"), app,
#'   scope = '',
#'   type  = "application/x-www-form-urlencoded")$credentials$access_token
#'
#' ## Then pass this token with your account ID to fbad_init
#' }
fbad_init <- function(accountid, token) {

    ## define parameters
    params <- list(
        acct_path     = paste0('act_', accountid, '/'),
        versioned_url = fbad_get_baseurl(),
        access_token  = token,
        api_version   = fbad_api_version
        )

    ## get account details
    details <- fbad_get_adaccount_details(accountid, token)

    ## add custom class and return
    structure(c(params, details), class = 'FB_Ad_Account')

}

#' Check if provided R object is a valid list of FB account details
#' @param fbacc R object
#' @keywords intenral
fbad_check_fbacc <- function(fbacc) {

    if (missing(fbacc))
        stop('Please initialize and pass your FB Ad account object. See ?fbad_init for more details.')
    if (!inherits(fbacc, 'FB_Ad_Account'))
        stop('Invalid R object passed as fbacc argument. See ?fbad_init for more details.')

}


#' Print method for custom fbRads class
#' @param x R object with \code{FB_Ad_Account} class
#' @param ... further arguments passed to \code{print} (ignored)
#' @export
print.FB_Ad_Account <- function(x, ...) {
    cat(paste0('Facebook Ad API connection parameters for <<', x$name, '>>.'), '\n')
}
