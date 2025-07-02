LSL_SRC=./src/liblsl-9e3823bb
emcc -sEXPORT_NAME=liblsl --no-entry \
      -sENVIRONMENT=web,worker,node -DVERSION=1.16.2 -DLSL_ABI_VERSION=2 \
      -DLOGURU_PTHREADS=0 -DLOGURU_WITH_STREAMS=0 \
      -DASIO_DISABLE_THREADS -D_POSIX_C_SOURCE=200809L \
      --std=c++17 -sERROR_ON_UNDEFINED_SYMBOLS=0 -sALLOW_MEMORY_GROWTH=1 \
      -sNO_DISABLE_EXCEPTION_CATCHING \
      --js-library stub_pthread.js \
      -sEXPORTED_FUNCTIONS=_lsl_last_error,_lsl_protocol_version,_lsl_library_version,_lsl_library_info,_lsl_local_clock,_lsl_destroy_string,_lsl_set_config_filename,_lsl_set_config_content,_lsl_create_inlet,_lsl_create_inlet_ex,_lsl_destroy_inlet,_lsl_get_fullinfo,_lsl_open_stream,_lsl_close_stream,_lsl_time_correction,_lsl_time_correction_ex,_lsl_set_postprocessing,_lsl_pull_sample_f,_lsl_pull_sample_d,_lsl_pull_sample_l,_lsl_pull_sample_i,_lsl_pull_sample_s,_lsl_pull_sample_c,_lsl_pull_sample_str,_lsl_pull_sample_buf,_lsl_pull_sample_v,_lsl_pull_chunk_f,_lsl_pull_chunk_d,_lsl_pull_chunk_l,_lsl_pull_chunk_i,_lsl_pull_chunk_s,_lsl_pull_chunk_c,_lsl_pull_chunk_str,_lsl_pull_chunk_buf,_lsl_samples_available,_lsl_inlet_flush,_lsl_was_clock_reset,_lsl_smoothing_halftime,_lsl_create_outlet,_lsl_create_outlet_ex,_lsl_destroy_outlet,_lsl_push_sample_f,_lsl_push_sample_d,_lsl_push_sample_l,_lsl_push_sample_i,_lsl_push_sample_s,_lsl_push_sample_c,_lsl_push_sample_str,_lsl_push_sample_v,_lsl_push_sample_ft,_lsl_push_sample_dt,_lsl_push_sample_lt,_lsl_push_sample_it,_lsl_push_sample_st,_lsl_push_sample_ct,_lsl_push_sample_strt,_lsl_push_sample_vt,_lsl_push_sample_ftp,_lsl_push_sample_dtp,_lsl_push_sample_ltp,_lsl_push_sample_itp,_lsl_push_sample_stp,_lsl_push_sample_ctp,_lsl_push_sample_strtp,_lsl_push_sample_vtp,_lsl_push_sample_buf,_lsl_push_sample_buft,_lsl_push_sample_buftp,_lsl_push_chunk_f,_lsl_push_chunk_d,_lsl_push_chunk_l,_lsl_push_chunk_i,_lsl_push_chunk_s,_lsl_push_chunk_c,_lsl_push_chunk_str,_lsl_push_chunk_ft,_lsl_push_chunk_dt,_lsl_push_chunk_lt,_lsl_push_chunk_it,_lsl_push_chunk_st,_lsl_push_chunk_ct,_lsl_push_chunk_strt,_lsl_push_chunk_ftp,_lsl_push_chunk_dtp,_lsl_push_chunk_ltp,_lsl_push_chunk_itp,_lsl_push_chunk_stp,_lsl_push_chunk_ctp,_lsl_push_chunk_strtp,_lsl_push_chunk_ftn,_lsl_push_chunk_dtn,_lsl_push_chunk_ltn,_lsl_push_chunk_itn,_lsl_push_chunk_stn,_lsl_push_chunk_ctn,_lsl_push_chunk_strtn,_lsl_push_chunk_ftnp,_lsl_push_chunk_dtnp,_lsl_push_chunk_ltnp,_lsl_push_chunk_itnp,_lsl_push_chunk_stnp,_lsl_push_chunk_ctnp,_lsl_push_chunk_strtnp,_lsl_push_chunk_buf,_lsl_push_chunk_buft,_lsl_push_chunk_buftp,_lsl_push_chunk_buftn,_lsl_push_chunk_buftnp,_lsl_have_consumers,_lsl_wait_for_consumers,_lsl_get_info,_lsl_create_continuous_resolver,_lsl_create_continuous_resolver_byprop,_lsl_create_continuous_resolver_bypred,_lsl_resolver_results,_lsl_destroy_continuous_resolver,_lsl_resolve_all,_lsl_resolve_byprop,_lsl_resolve_bypred,_lsl_create_streaminfo,_lsl_destroy_streaminfo,_lsl_copy_streaminfo,_lsl_get_name,_lsl_get_type,_lsl_get_channel_count,_lsl_get_nominal_srate,_lsl_get_channel_format,_lsl_get_source_id,_lsl_get_version,_lsl_get_created_at,_lsl_get_uid,_lsl_get_session_id,_lsl_get_hostname,_lsl_get_desc,_lsl_get_xml,_lsl_get_channel_bytes,_lsl_get_sample_bytes,_lsl_stream_info_matches_query,_lsl_streaminfo_from_xml,_lsl_first_child,_lsl_last_child,_lsl_next_sibling,_lsl_previous_sibling,_lsl_parent,_lsl_child,_lsl_next_sibling_n,_lsl_previous_sibling_n,_lsl_empty,_lsl_is_text,_lsl_name,_lsl_value,_lsl_child_value,_lsl_child_value_n,_lsl_append_child_value,_lsl_prepend_child_value,_lsl_set_child_value,_lsl_set_name,_lsl_set_value,_lsl_append_child,_lsl_prepend_child,_lsl_append_copy,_lsl_prepend_copy,_lsl_remove_child_n,_lsl_remove_child \
      -sEXPORTED_RUNTIME_METHODS=ccall,cwrap,allocateUTF8,stringToUTF8,UTF8ToString \
      -DASIO_NO_DEPRECATED -DBOOST_ALL_NO_LIB -DLIBLSL_EXPORTS \
      -DLSL_VERSION_INFO=git:x/branch:x/build:dart_native/compiler:unknown \
      -DLOGURU_STACKTRACES=0 -include ./src/include/lsl_lib_version.h \
      -I$LSL_SRC/lslboost -I$LSL_SRC/include \
      -I$LSL_SRC/thirdparty \
      -I$LSL_SRC/thirdparty/asio \
      -I$LSL_SRC/thirdparty/loguru \
      -I$LSL_SRC/thirdparty/pugixml \
      $LSL_SRC/src/buildinfo.cpp \
      $LSL_SRC/src/api_config.cpp \
      $LSL_SRC/src/cancellation.cpp \
      $LSL_SRC/src/common.cpp \
      $LSL_SRC/src/consumer_queue.cpp \
      $LSL_SRC/src/data_receiver.cpp \
      $LSL_SRC/src/info_receiver.cpp \
      $LSL_SRC/src/inlet_connection.cpp \
      $LSL_SRC/src/lsl_resolver_c.cpp \
      $LSL_SRC/src/lsl_inlet_c.cpp \
      $LSL_SRC/src/lsl_outlet_c.cpp \
      $LSL_SRC/src/lsl_streaminfo_c.cpp \
      $LSL_SRC/src/lsl_xml_element_c.cpp \
      $LSL_SRC/src/netinterfaces.cpp \
      $LSL_SRC/src/resolver_impl.cpp \
      $LSL_SRC/src/resolve_attempt_udp.cpp \
      $LSL_SRC/src/sample.cpp \
      $LSL_SRC/src/send_buffer.cpp \
      $LSL_SRC/src/socket_utils.cpp \
      $LSL_SRC/src/stream_info_impl.cpp \
      $LSL_SRC/src/stream_outlet_impl.cpp \
      $LSL_SRC/src/tcp_server.cpp \
      $LSL_SRC/src/time_postprocessor.cpp \
      $LSL_SRC/src/time_receiver.cpp \
      $LSL_SRC/src/udp_server.cpp \
      $LSL_SRC/src/util/cast.cpp \
      $LSL_SRC/src/util/endian.cpp \
      $LSL_SRC/src/util/inireader.cpp \
      $LSL_SRC/src/util/strfuns.cpp \
      $LSL_SRC/thirdparty/pugixml/pugixml.cpp \
      $LSL_SRC/thirdparty/loguru/loguru.cpp \
      -o ./liblsl.js
